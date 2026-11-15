import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';

// Widget tests have no raster thread. Explicitly acknowledge a simulated raster
// completion; production uses the engine's FrameTiming reports.
Future<void> rasterize(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final t = tester.binding.currentSystemFrameTimeStamp.inMicroseconds;
  tester.platformDispatcher.onReportTimings?.call([
    ui.FrameTiming(
      vsyncStart: t,
      buildStart: t,
      buildFinish: t + 1,
      rasterStart: t + 2,
      rasterFinish: t + 3,
      rasterFinishWallTime: t + 3,
    ),
  ]);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_screen_protection');
  final key = GlobalKey<NavigatorState>();
  final boundary = GlobalKey();
  final calls = <bool>[];
  final paints = <String, int>{};
  final routes = <Route<dynamic>>[];
  Completer<void>? delay;
  bool fail = false;

  setUp(() {
    calls.clear();
    paints.clear();
    routes.clear();
    delay = null;
    fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final blocked = (call.arguments as Map)['blocked'] as bool;
          calls.add(blocked);
          if (blocked && delay != null) await delay!.future;
          if (fail) throw PlatformException(code: 'window_update_failed');
          return null;
        });
  });

  Future<void> start(WidgetTester tester) async {
    await FlutterScreenProtection.initialize(
      screenshotsEnabled: true,
      protectedRoutes: ['/transfer', '/login'],
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        restorationScopeId: 'automatic',
        navigatorObservers: [FlutterScreenProtection.navigatorObserver],
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: FlutterScreenProtection.builder(context, child),
        ),
        initialRoute: '/home',
        onGenerateRoute: (settings) {
          final route = MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => CustomPaint(
              painter: _ProbePainter(
                settings.name == '/transfer' || settings.name == '/login'
                    ? Colors.red
                    : Colors.green,
                () => paints.update(
                  settings.name!,
                  (v) => v + 1,
                  ifAbsent: () => 1,
                ),
              ),
              child: const SizedBox.expand(),
            ),
          );
          routes.add(route);
          return route;
        },
      ),
    );
    await rasterize(tester);
    expect(calls.last, false);
  }

  Future<void> expectBlack(WidgetTester tester) async {
    final rgba = await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final i = (image.width * (image.height ~/ 2) + image.width ~/ 2) * 4;
      final color = data!.buffer.asUint8List().sublist(i, i + 4);
      image.dispose();
      return color;
    });
    expect(rgba, [0, 0, 0, 255]);
  }

  testWidgets(
    'unmodified pushNamed withholds first protected paint until acknowledgement',
    (tester) async {
      await start(tester);
      delay = Completer<void>();
      Navigator.pushNamed(key.currentContext!, '/transfer');
      await tester.pumpAndSettle();
      expect(paints['/transfer'] ?? 0, 0);
      await expectBlack(tester);
      delay!.complete();
      await tester.pumpAndSettle();
      expect(paints['/transfer'], greaterThan(0));
      expect(calls.last, true);
      Navigator.pop(key.currentContext!);
      await tester.pumpAndSettle();
      expect(calls.last, true, reason: 'release waits for raster completion');
      await rasterize(tester);
      expect(calls.last, false);
    },
  );

  testWidgets('idle release retries a safe frame without timing out open', (
    tester,
  ) async {
    await start(tester);
    Navigator.pushNamed(key.currentContext!, '/transfer');
    await rasterize(tester);
    Navigator.pop(key.currentContext!);
    await tester.pumpAndSettle();
    var paintedFrame = false;
    tester.binding.addPostFrameCallback((_) => paintedFrame = true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(paintedFrame, true);
    expect(
      calls.last,
      true,
      reason: 'repaint retry is not permission to clear',
    );
    await rasterize(tester);
    expect(calls.last, false);
    paintedFrame = false;
    tester.binding.addPostFrameCallback((_) => paintedFrame = true);
    await tester.pump(const Duration(seconds: 2));
    expect(paintedFrame, false, reason: 'retry stops after acknowledgement');
  });

  testWidgets(
    'unmodified replacement and pop revealing a cached protected page are gated',
    (tester) async {
      await start(tester);
      Navigator.pushNamed(key.currentContext!, '/transfer');
      await rasterize(tester);
      Navigator.pushNamed(key.currentContext!, '/home');
      await rasterize(tester);
      expect(calls.last, false);
      delay = Completer<void>();
      Navigator.pop(key.currentContext!);
      await tester.pumpAndSettle();
      await expectBlack(tester); // Includes previously retained repaint layers.
      delay!.complete();
      await rasterize(tester);
      delay = Completer<void>();
      Navigator.pushReplacementNamed(key.currentContext!, '/home');
      await rasterize(tester);
      Navigator.pushReplacementNamed(key.currentContext!, '/login');
      await tester.pumpAndSettle();
      expect(paints['/login'] ?? 0, 0);
      await expectBlack(tester);
      delay!.complete();
      await rasterize(tester);
      expect(paints['/login'], greaterThan(0));
    },
  );

  testWidgets(
    'native failure remains closed and explicit successful retry recovers',
    (tester) async {
      await start(tester);
      fail = true;
      final errors = <Object>[];
      final handler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      Navigator.pushNamed(key.currentContext!, '/transfer');
      await tester.pumpAndSettle();
      FlutterError.onError = handler;
      expect(errors, isNotEmpty);
      expect(errors, everyElement(isA<PlatformException>()));
      expect(paints['/transfer'] ?? 0, 0);
      await expectBlack(tester);
      fail = false;
      await FlutterScreenProtection.setScreenshotsEnabled(false);
      await tester.pumpAndSettle();
      expect(paints['/transfer'], greaterThan(0));
      expect(calls.last, true);
    },
  );

  testWidgets(
    'predictive gesture gates cached underlying route and cancellation restores allowance',
    (tester) async {
      await start(tester);
      Navigator.pushNamed(key.currentContext!, '/transfer');
      await rasterize(tester);
      Navigator.pushNamed(key.currentContext!, '/home');
      await rasterize(tester);
      delay = Completer<void>();
      final top = routes.last as TransitionRoute<void>;
      top.handleStartBackGesture(progress: 1);
      top.handleUpdateBackGestureProgress(progress: 0.5);
      await tester.pump();
      await expectBlack(tester);
      delay!.complete();
      await tester.pump();
      top.handleCancelBackGesture();
      await rasterize(tester);
      expect(calls.last, false);
      top.handleStartBackGesture(progress: 1);
      top.handleUpdateBackGestureProgress(progress: 0.5);
      await tester.pump();
      top.handleCommitBackGesture();
      await rasterize(tester);
      expect(calls.last, true);
    },
  );

  testWidgets('rapid navigation, backend precedence, removal and restoration', (
    tester,
  ) async {
    await start(tester);
    Navigator.pushNamed(key.currentContext!, '/transfer');
    Navigator.pop(key.currentContext!);
    Navigator.pushReplacementNamed(key.currentContext!, '/login');
    await FlutterScreenProtection.setScreenshotsEnabled(false);
    await rasterize(tester);
    expect(calls.last, true);
    key.currentState!.pushNamedAndRemoveUntil('/home', (_) => false);
    await rasterize(tester);
    expect(calls.last, true);
    final enable = FlutterScreenProtection.setScreenshotsEnabled(true);
    await rasterize(tester);
    await enable;
    expect(calls.last, false);
  });

  testWidgets(
    'late acknowledgements cannot open a newer protected navigation',
    (tester) async {
      await start(tester);
      delay = Completer<void>();
      final oldAck = delay!;
      final disable = FlutterScreenProtection.setScreenshotsEnabled(false);
      await tester.pump();
      await expectBlack(tester);
      final enable = FlutterScreenProtection.setScreenshotsEnabled(true);
      await rasterize(tester);
      await enable;
      delay = Completer<void>();
      Navigator.pushNamed(key.currentContext!, '/transfer');
      await tester.pumpAndSettle();
      oldAck.complete();
      await disable;
      await tester.pump();
      await expectBlack(tester);
      expect(paints['/transfer'] ?? 0, 0);
      delay!.complete();
      await rasterize(tester);
      expect(paints['/transfer'], greaterThan(0));
    },
  );

  testWidgets(
    'backend failure and route-list changes fail closed and recover',
    (tester) async {
      await start(tester);
      fail = true;
      await expectLater(
        FlutterScreenProtection.setScreenshotsEnabled(false),
        throwsA(isA<PlatformException>()),
      );
      await tester.pump();
      await expectBlack(tester);
      fail = false;
      final retry = FlutterScreenProtection.setScreenshotsEnabled(true);
      await rasterize(tester);
      await retry;
      expect(calls.last, false);
      delay = Completer<void>();
      final protect = FlutterScreenProtection.setProtectedRoutes(['/home']);
      await tester.pump();
      await expectBlack(tester);
      delay!.complete();
      await protect;
      await tester.pump();
      expect(calls.last, true);
      final allow = FlutterScreenProtection.setProtectedRoutes([]);
      await rasterize(tester);
      await allow;
      expect(calls.last, false);
    },
  );

  testWidgets('restorable routes and system back use the same root gate', (
    tester,
  ) async {
    await start(tester);
    key.currentState!.restorablePushNamed('/transfer');
    await rasterize(tester);
    await tester.restartAndRestore();
    await rasterize(tester);
    expect(calls.last, true);
    await tester.binding.handlePopRoute();
    await rasterize(tester);
    expect(calls.last, false);
  });
}

class _ProbePainter extends CustomPainter {
  _ProbePainter(this.color, this.onPaint);
  final Color color;
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ProbePainter oldDelegate) => true;
}
