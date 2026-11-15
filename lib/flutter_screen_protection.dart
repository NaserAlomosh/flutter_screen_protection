import 'dart:async';
import 'dart:ui' show FramePhase, FrameTiming;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android-only screenshot policy. Unknown routes are always protected.
abstract final class FlutterScreenProtection {
  static const _channel = MethodChannel('flutter_screen_protection');
  static bool _enabled = false;
  static Set<String> _routes = {};
  static int _guards = 0;
  static final _observer = _ProtectionObserver();
  static final _gates = <_RenderProtectionGate>{};
  static int _revision = 0;
  static bool _acknowledgedSecure = false;
  static bool _lastSentSecure = true;
  static bool _failed = false;
  static _SafeFrame? _release;

  /// Install once as MaterialApp.builder, together with [navigatorObserver].
  /// Withholds the complete Navigator paint subtree until protection is acknowledged.
  /// Screen widgets and navigation calls need no changes.
  static Widget builder(BuildContext context, Widget? child) =>
      _ProtectionGate(child: child ?? const SizedBox.expand());

  static bool get _requiresProtection =>
      !_enabled || _guards > 0 || _observer.blocks(_protected);

  static bool get _canPaint =>
      !_failed && (!_requiresProtection || _acknowledgedSecure);

  static void _invalidateGates() {
    for (final gate in _gates) {
      gate.markNeedsPaint();
      gate.markNeedsSemanticsUpdate();
    }
  }

  static void _onTimings(List<FrameTiming> timings) {
    final release = _release;
    if (release == null || release.paintTime == null) return;
    if (timings.any(
      (frame) =>
          frame.timestampInMicroseconds(FramePhase.buildStart) >=
          release.paintTime!,
    )) {
      _release = null;
      release.finish();
    }
  }

  static void _paintedAllowedFrame() {
    if (!_requiresProtection) {
      _release?.paintTime ??=
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
    }
  }

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
  /// Optional legacy helper. Not needed with [builder] and [navigatorObserver].
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

  static Future<void> _sync() async {
    final revision = ++_revision;
    final blocked = _requiresProtection;
    final superseded = _release;
    _release = null;
    superseded?.finish();

    // Keep FLAG_SECURE until a frame without protected content has rasterized.
    // Register before invalidation, so that even an otherwise idle frame is painted.
    final release =
        !blocked &&
            _gates.isNotEmpty &&
            (_lastSentSecure || _acknowledgedSecure)
        ? _SafeFrame()
        : null;
    _release = release;
    _invalidateGates();
    if (release != null) await release.done.future;
    if (revision != _revision) return;

    _lastSentSecure = blocked;
    if (!blocked) _acknowledgedSecure = false;
    try {
      await _channel.invokeMethod<void>('setProtection', {'blocked': blocked});
      if (revision != _revision) return;
      _acknowledgedSecure = blocked;
      _failed = false;
      _invalidateGates();
    } catch (_) {
      if (revision == _revision) {
        _acknowledgedSecure = false;
        _failed = true;
        _invalidateGates();
      }
      rethrow;
    }
  }

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
  bool _gesture = false;
  final Set<Route<dynamic>> _outgoing = {};
  final Set<Route<dynamic>> _settled = {};
  final Map<TransitionRoute<dynamic>, AnimationStatusListener> _listeners = {};

  bool blocks(bool Function(Route<dynamic>) protected) {
    if (_stack.isEmpty) return true;
    if (_gesture && _stack.any(protected)) return true;
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
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    _gesture = true;
    FlutterScreenProtection._changed();
  }

  @override
  void didStopUserGesture() {
    _gesture = false;
    FlutterScreenProtection._changed();
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

class _SafeFrame {
  _SafeFrame() {
    // An idle/dropped frame can leave no matching raster report. Request another
    // safe frame until the engine acknowledges one; never release on a timeout.
    _retry = Timer.periodic(const Duration(milliseconds: 100), (_) {
      FlutterScreenProtection._invalidateGates();
      SchedulerBinding.instance.scheduleFrame();
    });
  }

  late final Timer _retry;
  void finish() {
    _retry.cancel();
    done.complete();
  }

  final done = Completer<void>();
  int? paintTime;
}

class _ProtectionGate extends SingleChildRenderObjectWidget {
  const _ProtectionGate({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProtectionGate();
}

/// A paint boundary, not an overlay placed on top of already-painted content.
/// Closed frames never append the Navigator's retained layers to the scene.
class _RenderProtectionGate extends RenderProxyBox {
  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (FlutterScreenProtection._gates.isEmpty) {
      SchedulerBinding.instance.addTimingsCallback(
        FlutterScreenProtection._onTimings,
      );
    }
    FlutterScreenProtection._gates.add(this);
  }

  @override
  void detach() {
    FlutterScreenProtection._gates.remove(this);
    if (FlutterScreenProtection._gates.isEmpty) {
      SchedulerBinding.instance.removeTimingsCallback(
        FlutterScreenProtection._onTimings,
      );
      final release = FlutterScreenProtection._release;
      FlutterScreenProtection._release = null;
      release?.finish();
    }
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (FlutterScreenProtection._canPaint) {
      super.paint(context, offset);
      FlutterScreenProtection._paintedAllowedFrame();
    } else {
      context.canvas.drawRect(
        offset & size,
        Paint()..color = const Color(0xff000000),
      );
      FlutterScreenProtection._paintedAllowedFrame();
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      FlutterScreenProtection._canPaint &&
      super.hitTestChildren(result, position: position);

  @override
  bool hitTestSelf(Offset position) => !FlutterScreenProtection._canPaint;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (FlutterScreenProtection._canPaint) {
      super.visitChildrenForSemantics(visitor);
    }
  }
}
