import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('Automatic navigation screenshot matrix', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8765);
    final requests = StreamIterator<HttpRequest>(server);
    addTearDown(() async {
      await requests.cancel();
      await server.close(force: true);
    });
    final key = GlobalKey<NavigatorState>();
    const control = MethodChannel('fsp.validation');
    final sdk = await control.invokeMethod<int>('sdkInt') ?? 0;
    bool slow = false;
    await FlutterScreenProtection.initialize(protectedRoutes: ['/transfer']);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        builder: FlutterScreenProtection.builder,
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
            },
          ),
        ),
        navigatorObservers: [FlutterScreenProtection.navigatorObserver],
        initialRoute: '/home',
        onGenerateRoute: (settings) {
          final route = _TimedRoute(
            duration: slow
                ? const Duration(seconds: 6)
                : const Duration(milliseconds: 300),
            settings: settings,
            builder: (_) => Scaffold(
              backgroundColor: settings.name == '/transfer'
                  ? const Color(0xffe02040)
                  : const Color(0xff20c060),
              body: Center(
                child: Text(
                  'VISIBLE CONTENT ${settings.name}',
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),
          );
          return route;
        },
      ),
    );
    Future<void> evidence(String name, bool blocked) async {
      await tester.pumpAndSettle();
      // External ADB runner captures the real composed display during this interval.
      // ignore: avoid_print
      print('FSP_EVIDENCE $name ${blocked ? "BLOCKED" : "ALLOWED"}');
      await tester.runAsync(() async {
        if (!await requests.moveNext().timeout(const Duration(seconds: 60))) {
          throw StateError('Evidence runner disconnected');
        }
        await requests.current.response.close();
      });
    }

    await evidence('startup', true);
    await FlutterScreenProtection.setScreenshotsEnabled(true);
    await evidence('global_enabled_home', false);
    await FlutterScreenProtection.setScreenshotsEnabled(false);
    await evidence('global_disabled', true);
    await FlutterScreenProtection.setScreenshotsEnabled(true);
    await evidence('backend_reenabled', false);
    Navigator.pushNamed(key.currentContext!, '/transfer');
    await evidence('protected_transfer', true);
    key.currentState!.pop();
    await evidence('pop_home', false);
    key.currentState!.pushNamed('/transfer');
    await evidence('system_back', false);
    await FlutterScreenProtection.setProtectedRoutes(['/home', '/transfer']);
    await evidence('route_list_add', true);
    await FlutterScreenProtection.setProtectedRoutes(['/transfer']);
    await evidence('route_list_remove', false);
    key.currentState!.pushReplacementNamed('/transfer');
    await evidence('replacement_protected', true);
    key.currentState!.pushNamedAndRemoveUntil('/home', (_) => false);
    await evidence('remove_until_home', false);
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/transfer'),
      builder: (_) => const Text('transfer'),
    );
    key.currentState!.push(route);
    await tester.pumpAndSettle();
    key.currentState!.removeRoute(route);
    await evidence('remove_route', false);
    key.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('unnamed')),
    );
    await evidence('unnamed', true);
    key.currentState!.pop();
    await FlutterScreenProtection.setScreenshotsEnabled(false);
    key.currentState!.pushNamed('/transfer');
    key.currentState!.pop();
    await evidence('global_precedence_rapid_navigation', true);
    await Future.wait(
      List.generate(
        20,
        (i) => FlutterScreenProtection.setScreenshotsEnabled(i.isOdd),
      ),
    );
    await evidence('rapid_updates_final_allowed', false);
    await evidence('lifecycle_allowed', false);
    await FlutterScreenProtection.setScreenshotsEnabled(false);
    await evidence('lifecycle_secure', true);
    await FlutterScreenProtection.setScreenshotsEnabled(true);
    await evidence('automatic_home', false);
    Future<void> samples(String name, String mode) async {
      // ignore: avoid_print
      print('FSP_TRANSITION $name $mode');
      await tester.runAsync(() async {
        if (!await requests.moveNext().timeout(const Duration(seconds: 60))) {
          throw StateError('runner disconnected');
        }
        await requests.current.response.close();
      });
    }

    slow = true;
    await control.invokeMethod<void>('configure', {'delayMillis': 5000});
    Navigator.pushNamed(key.currentContext!, '/transfer');
    await tester.pump();
    await samples('delayed_push_first_frames', 'GATED');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    await control.invokeMethod<void>('configure', {});
    await evidence('delayed_push_acknowledged', true);
    slow = true;
    Navigator.pushNamed(key.currentContext!, '/home');
    await tester.pump();
    await samples('protected_to_allowed_push', 'SECURE');
    await evidence('allowed_after_transition', false);
    await control.invokeMethod<void>('configure', {'delayMillis': 5000});
    Navigator.pop(key.currentContext!);
    await tester.pump();
    await samples('delayed_pop_cached_protected', 'GATED');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    await control.invokeMethod<void>('configure', {});
    await evidence('cached_protected_acknowledged', true);
    Navigator.pop(key.currentContext!);
    await tester.pump();
    await samples('protected_pop_to_home', 'SECURE');
    await evidence('home_after_pop_transition', false);
    await control.invokeMethod<void>('configure', {'fail': true});
    final errors = <Object>[];
    final errorHandler = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    Navigator.pushReplacementNamed(key.currentContext!, '/transfer');
    await tester.pumpAndSettle();
    await samples('native_failure_gate', 'GATED');
    expect(errors, isNotEmpty);
    FlutterError.onError = errorHandler;
    await control.invokeMethod<void>('configure', {});
    await FlutterScreenProtection.setScreenshotsEnabled(true);
    await evidence('native_failure_retry', true);
    Navigator.pushNamed(key.currentContext!, '/home');
    await evidence('before_predictive', false);
    if (sdk >= 34) {
      final started = await control.invokeMethod<bool>('back', {
        'event': 'startBackGesture',
        'payload': {
          'touchOffset': [1.0, 400.0],
          'progress': 0.0,
          'swipeEdge': 0,
        },
      });
      expect(started, true);
      await control.invokeMethod<void>('back', {
        'event': 'updateBackGestureProgress',
        'payload': {
          'touchOffset': [200.0, 400.0],
          'progress': 0.4,
          'swipeEdge': 0,
        },
      });
      await tester.pump();
      await samples('predictive_progress_native_callback', 'SECURE');
      await control.invokeMethod<void>('back', {'event': 'cancelBackGesture'});
      await evidence('predictive_cancel', false);
      await control.invokeMethod<bool>('back', {
        'event': 'startBackGesture',
        'payload': {
          'touchOffset': [1.0, 400.0],
          'progress': 0.0,
          'swipeEdge': 0,
        },
      });
      await control.invokeMethod<void>('back', {
        'event': 'updateBackGestureProgress',
        'payload': {
          'touchOffset': [200.0, 400.0],
          'progress': 0.4,
          'swipeEdge': 0,
        },
      });
      await control.invokeMethod<void>('back', {'event': 'commitBackGesture'});
      await evidence('predictive_commit', true);
      Navigator.pushNamed(key.currentContext!, '/home');
      await evidence('before_os_predictive', false);
      final notifier = key.currentState!.userGestureInProgressNotifier;
      void gestureChanged() {
        if (notifier.value) {
          // ignore: avoid_print
          print('FSP_OS_GESTURE_STARTED');
        }
      }

      // This harness recreates an Activity while retaining its engine. Refresh
      // the framework back registration on the new Activity before OS injection.
      await SystemNavigator.setFrameworkHandlesBack(false);
      await SystemNavigator.setFrameworkHandlesBack(true);
      notifier.addListener(gestureChanged);
      await samples('os_predictive_back', 'GESTURE');
      notifier.removeListener(gestureChanged);
    }
    // ignore: avoid_print
    print('FSP_MATRIX_DONE');
  });
}

class _TimedRoute extends MaterialPageRoute<void> {
  _TimedRoute({
    required this.duration,
    required super.settings,
    required super.builder,
  });
  final Duration duration;
  @override
  Duration get transitionDuration => duration;
  @override
  Duration get reverseTransitionDuration => duration;
}
