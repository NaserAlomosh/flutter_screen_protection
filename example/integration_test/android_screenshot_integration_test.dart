import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const expected = String.fromEnvironment('FSP_SCREENSHOT_EXPECTED');
  const takeScreenshot = bool.fromEnvironment('FSP_TAKE_SCREENSHOT');

  testWidgets(
    'Android screenshot capability and continuous state',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('Screenshot validation'))),
        ),
      );
      final controller = FlutterScreenProtectionController();
      addTearDown(controller.dispose);
      final settled = Completer<void>();
      void checkActivity() {
        final reason = controller.capabilities.screenshots.reason;
        if (!settled.isCompleted &&
            reason != CaptureReason.initializing &&
            reason != CaptureReason.detached &&
            reason != CaptureReason.backgrounded) {
          settled.complete();
        }
      }

      controller.state.addListener(checkActivity);
      try {
        await controller.initialize();
        checkActivity();
        await settled.future.timeout(const Duration(seconds: 10));
      } finally {
        controller.state.removeListener(checkActivity);
      }

      final screenshots = controller.capabilities.screenshots;
      expect(
        await const ChannelCapturePlatform().queryCapabilities(),
        controller.capabilities,
      );
      if (expected == 'supported') {
        expect(screenshots.support, CaptureSupport.supported);
        expect(screenshots.scope, CaptureScope.activity);
      } else if (expected == 'unsupported') {
        expect(screenshots.support, CaptureSupport.unavailable);
        expect(screenshots.reason, CaptureReason.unsupportedOs);
      } else if (expected == 'permissionMissing') {
        expect(screenshots.support, CaptureSupport.unavailable);
        expect(screenshots.reason, CaptureReason.permissionMissing);
        expect(controller.state.value.status, CaptureStatus.unknown);
      }
      expect(
        controller.capabilities.continuousCapture.support,
        CaptureSupport.unavailable,
      );
      expect(controller.state.value.status, isNot(CaptureStatus.active));

      if (takeScreenshot) {
        expect(screenshots.support, CaptureSupport.supported);
        final stateBeforeCapture = controller.state.value;
        final event = controller.captureEvents
            .where((event) => event is ScreenshotTaken)
            .first
            .timeout(const Duration(minutes: 1));
        debugPrint(
          'FSP_SCREENSHOT_READY: use the device screenshot button combination',
        );
        final screenshot = await event;
        expect(screenshot.scope, CaptureScope.activity);
        expect(screenshot.sequence, 1);
        expect(controller.state.value, stateBeforeCapture);
        debugPrint('FSP_SCREENSHOT_RECEIVED');
      }
    },
    skip: !Platform.isAndroid,
  );
}
