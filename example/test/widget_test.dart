import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screen_protection_example/main.dart' as app;

void main() {
  testWidgets('example exposes backend and route configuration controls', (
    tester,
  ) async {
    final policies = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_screen_protection'),
          (call) async {
            policies.add((call.arguments as Map)['blocked'] as bool);
            return null;
          },
        );
    await app.main();
    await rasterize(tester);
    expect(policies.last, true);
    await tester.tap(find.byType(Switch).first);
    await rasterize(tester);
    expect(policies.last, false);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, true);
    await tester.tap(find.text('Open /transfer'));
    await rasterize(tester);
    expect(policies.last, true);
    expect(find.text('SCREEN CONTENT: /transfer'), findsOneWidget);
    await tester.pageBack();
    await rasterize(tester);
    expect(policies.last, false);
    await tester.tap(find.byType(Switch).last);
    await rasterize(tester);
    expect(policies.last, true);
  });
}

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
