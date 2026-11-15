import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <bool>[];
  const channel = MethodChannel('flutter_screen_protection');
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expectSync(call.method, 'setProtection');
          calls.add((call.arguments as Map)['blocked'] as bool);
          return null;
        });
  });
  testWidgets(
    'policy precedence, transitions, runtime updates and navigation',
    (tester) async {
      await FlutterScreenProtection.initialize();
      expect(calls.last, true);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [FlutterScreenProtection.navigatorObserver],
          initialRoute: '/home',
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => Text(settings.name ?? 'unknown'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await FlutterScreenProtection.setScreenshotsEnabled(true);
      expect(calls.last, false);
      await FlutterScreenProtection.setProtectedRoutes(['/transfer']);
      key.currentState!.pushNamed('/transfer');
      await tester.pumpAndSettle();
      expect(calls.last, true);
      key.currentState!.pop();
      await tester.pump();
      expect(
        calls.last,
        true,
        reason: 'outgoing sensitive route still visible',
      );
      await tester.pumpAndSettle();
      expect(calls.last, false);
      await FlutterScreenProtection.setProtectedRoutes(['/home']);
      expect(calls.last, true);
      await FlutterScreenProtection.setProtectedRoutes([]);
      expect(calls.last, false);
      await FlutterScreenProtection.setScreenshotsEnabled(false);
      key.currentState!.pushReplacementNamed('/transactions');
      await tester.pumpAndSettle();
      expect(calls.last, true);
      await FlutterScreenProtection.setScreenshotsEnabled(true);
      expect(calls.last, false);
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('unnamed')),
      );
      await tester.pumpAndSettle();
      expect(calls.last, true);
      key.currentState!.pushNamedAndRemoveUntil('/home', (_) => false);
      await tester.pumpAndSettle();
      expect(calls.last, false);
      final pending = [
        FlutterScreenProtection.setScreenshotsEnabled(false),
        FlutterScreenProtection.setScreenshotsEnabled(true),
        FlutterScreenProtection.setProtectedRoutes(['/home']),
      ];
      await Future.wait(pending);
      expect(calls.last, true);
    },
  );
  testWidgets(
    'guard waits for Android acknowledgement and cleans up on errors',
    (tester) async {
      await FlutterScreenProtection.initialize(
        screenshotsEnabled: true,
        protectedRoutes: ['/transfer'],
      );
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [FlutterScreenProtection.navigatorObserver],
          initialRoute: '/transfer',
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Text('screen'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.last, true);
      key.currentState!.pushReplacementNamed('/home');
      await tester.pumpAndSettle();
      expect(calls.last, false);
      final acknowledgement = Completer<void>();
      var first = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add((call.arguments as Map)['blocked'] as bool);
            if (first) {
              first = false;
              await acknowledgement.future;
            }
            return null;
          });
      var navigated = false;
      final guarded = FlutterScreenProtection.protectNavigation(() {
        navigated = true;
        key.currentState!.pushNamed('/transfer');
      });
      await tester.pump();
      expect(navigated, false);
      expect(calls.last, true);
      acknowledgement.complete();
      await tester.pumpAndSettle();
      await guarded;
      expect(navigated, true);
      expect(calls.last, true);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(calls.last, false);
      await expectLater(
        FlutterScreenProtection.protectNavigation(
          () => throw StateError('cancelled'),
        ),
        throwsStateError,
      );
      expect(calls.last, false);
    },
  );
  testWidgets('restoration and nonopaque routes retain protection', (
    tester,
  ) async {
    await FlutterScreenProtection.initialize(
      screenshotsEnabled: true,
      protectedRoutes: ['/transfer'],
    );
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        restorationScopeId: 'test',
        navigatorKey: key,
        navigatorObservers: [FlutterScreenProtection.navigatorObserver],
        initialRoute: '/home',
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Text('screen'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.restorablePushNamed('/transfer');
    await tester.pumpAndSettle();
    expect(calls.last, true);
    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(calls.last, true);
    key.currentState!.push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: '/dialog'),
        opaque: false,
        pageBuilder: (_, _, _) => const Text('overlay'),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.last, true);
    key.currentState!.pop();
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls.last, false);
    key.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: ''),
        builder: (_) => const Text('empty name'),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.last, true);
  });
  test('invalid native response propagates to caller', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'window_update_failed'),
        );
    await expectLater(
      FlutterScreenProtection.setScreenshotsEnabled(false),
      throwsA(isA<PlatformException>()),
    );
  });
}
