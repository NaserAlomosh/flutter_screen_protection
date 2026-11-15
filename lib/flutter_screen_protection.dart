import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android-only screenshot policy. Unknown routes are always protected.
abstract final class FlutterScreenProtection {
  static const _channel = MethodChannel('flutter_screen_protection');
  static bool _enabled = false;
  static Set<String> _routes = {};
  static int _guards = 0;
  static final _observer = _ProtectionObserver();

  /// Register once on the application's single root Navigator.
  static NavigatorObserver get navigatorObserver => _observer;

  /// Call after ensureInitialized and before runApp. Defaults to fail closed.
  static Future<void> initialize({
    bool screenshotsEnabled = false,
    List<String> protectedRoutes = const [],
  }) {
    _enabled = screenshotsEnabled;
    _routes = Set.of(protectedRoutes);
    return _sync();
  }

  /// Replaces the backend policy. False always blocks, regardless of route.
  /// The Future completes after native application, or storage while detached.
  static Future<void> setScreenshotsEnabled(bool enabled) {
    _enabled = enabled;
    return _sync();
  }

  /// Replaces exact, case-sensitive protected names and reevaluates visible routes.
  /// Copies [routes]; later caller mutations do not change the policy.
  static Future<void> setProtectedRoutes(List<String> routes) {
    _routes = Set.of(routes);
    return _sync();
  }

  /// Acknowledge native protection BEFORE changing navigation or sensitive UI.
  /// Invoke navigation synchronously in [navigate]; do not return its pop future.
  /// Required for a strict first-frame guarantee when leaving an allowed screen.
  static Future<void> protectNavigation(VoidCallback navigate) async {
    _guards++;
    try {
      await _sync();
      navigate();
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      _guards--;
      await _sync();
    }
  }

  static bool _protected(Route<dynamic> route) =>
      route.settings.name == null ||
      route.settings.name!.isEmpty ||
      _routes.contains(route.settings.name);

  static Future<void> _sync() => _channel.invokeMethod<void>('setProtection', {
    'blocked': !_enabled || _guards > 0 || _observer.blocks(_protected),
  });

  static void _changed() {
    unawaited(
      _sync().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'flutter_screen_protection',
            context: ErrorDescription(
              'synchronizing Android screenshot policy',
            ),
          ),
        );
      }),
    );
  }
}

class _ProtectionObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];
  final Set<Route<dynamic>> _outgoing = {};
  final Set<Route<dynamic>> _settled = {};
  final Map<TransitionRoute<dynamic>, AnimationStatusListener> _listeners = {};

  bool blocks(bool Function(Route<dynamic>) protected) {
    if (_stack.isEmpty) return true;
    if (_outgoing.any(protected)) return true;
    for (final route in _stack.reversed) {
      if (protected(route)) return true;
      if (route is TransitionRoute && !_settled.contains(route)) {
        continue;
      }
      if (route is ModalRoute && route.opaque) break;
    }
    return false;
  }

  void _watch(Route<dynamic> route) {
    if (route is! TransitionRoute || _listeners.containsKey(route)) return;
    void listener(AnimationStatus status) {
      _settled.remove(route);
      if (status == AnimationStatus.completed) {
        unawaited(
          WidgetsBinding.instance.endOfFrame.then((_) {
            if (_stack.contains(route) &&
                route.animation?.status == AnimationStatus.completed) {
              _settled.add(route);
              FlutterScreenProtection._changed();
            }
          }),
        );
      } else {
        FlutterScreenProtection._changed();
      }
    }

    _listeners[route] = listener;
    route.animation?.addStatusListener(listener);
    listener(route.animation?.status ?? AnimationStatus.dismissed);
    unawaited(
      route.completed.then((_) {
        _stack.remove(route);
        _outgoing.remove(route);
        _settled.remove(route);
        _listeners.remove(route);
        // The route disposes its animation; no disposed controller is retained.
        FlutterScreenProtection._changed();
      }),
    );
  }

  void _retire(Route<dynamic> route) {
    _outgoing.add(route);
    // completed resolves after the transition's overlay has been removed.
    final done = route is TransitionRoute
        ? route.completed
        : Future<void>.value();
    unawaited(
      done.then((_) {
        _outgoing.remove(route);
        if (route is TransitionRoute) {
          final listener = _listeners.remove(route);
          if (listener != null) route.animation?.removeStatusListener(listener);
        }
        FlutterScreenProtection._changed();
      }),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _watch(route);
    FlutterScreenProtection._changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _retire(route);
    FlutterScreenProtection._changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _retire(route);
    FlutterScreenProtection._changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (oldRoute != null) {
      _stack.remove(oldRoute);
      _retire(oldRoute);
    }
    if (newRoute != null) {
      _stack.insert(index < 0 ? _stack.length : index, newRoute);
      _watch(newRoute);
    }
    FlutterScreenProtection._changed();
  }
}
