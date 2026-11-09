import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_capture_platform.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const events = MethodChannel('flutter_screen_protection/events');
  const commands = MethodChannel('flutter_screen_protection');
  const codec = StandardMethodCodec();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(commands, null);
  });

  Future<void> deliver(ByteData? data) async {
    final reply = Completer<void>();
    await messenger.handlePlatformMessage(
      events.name,
      data,
      (_) => reply.complete(),
    );
    await reply.future;
  }

  test(
    'real channel adapter gates early packets on listen acknowledgement',
    () async {
      final listening = Completer<void>();
      final acknowledge = Completer<void>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(events, (call) async {
        calls.add(call);
        if (call.method == 'listen') {
          listening.complete();
          await acknowledge.future;
        }
        return null;
      });
      final controller = FlutterScreenProtectionController();
      addTearDown(controller.dispose);
      final ready = controller.initialize();
      await listening.future;
      await deliver(codec.encodeSuccessEnvelope(packet('initialActive')));
      expect(controller.state.value.status, CaptureStatus.unknown);
      acknowledge.complete();
      await ready;
      expect(controller.state.value.status, CaptureStatus.active);
      await controller.dispose();
      expect(calls.map((call) => call.method), ['listen', 'cancel']);
      expect(calls.map((call) => call.arguments), [
        {'version': 1},
        {'version': 1},
      ]);
    },
  );

  test('Android screenshot fans out without activating recording', () async {
    final listening = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(events, (call) async {
      calls.add(call.method);
      if (call.method == 'listen') listening.complete();
      return null;
    });
    final controller = FlutterScreenProtectionController();
    addTearDown(controller.dispose);
    final first = controller.captureEvents.first;
    final second = controller.captureEvents.first;
    final ready = controller.initialize();
    final repeated = controller.initialize();
    await listening.future;

    await deliver(codec.encodeSuccessEnvelope(packet('unsupported')));
    await Future.wait([ready, repeated]);
    await controller.initialize();
    final before = controller.state.value;
    expect(before.status, CaptureStatus.unsupported);
    expect(
      controller.capabilities.screenshots.support,
      CaptureSupport.supported,
    );

    await deliver(codec.encodeSuccessEnvelope(packet('screenshot')));
    for (final event in await Future.wait([first, second])) {
      expect(event, isA<ScreenshotTaken>());
      expect(event.scope, CaptureScope.activity);
      expect(event.sequence, 1);
    }
    expect(controller.state.value, before);
    expect(
      controller.capabilities.continuousCapture.support,
      CaptureSupport.unavailable,
    );
    await controller.dispose();
    expect(calls, ['listen', 'cancel']);
  });

  test('Android below 34 exposes unsupported screenshot capability', () async {
    final listening = Completer<void>();
    messenger.setMockMethodCallHandler(events, (call) async {
      if (call.method == 'listen') listening.complete();
      return null;
    });
    final controller = FlutterScreenProtectionController();
    addTearDown(controller.dispose);
    final ready = controller.initialize();
    await listening.future;
    await deliver(codec.encodeSuccessEnvelope(packet('androidBelow34')));
    await ready;
    expect(
      controller.capabilities.screenshots.support,
      CaptureSupport.unavailable,
    );
    expect(
      controller.capabilities.screenshots.reason,
      CaptureReason.unsupportedOs,
    );
    expect(controller.state.value.status, CaptureStatus.unsupported);
  });

  test(
    'missing native registration completes with a safe typed failure',
    () async {
      final controller = FlutterScreenProtectionController();
      addTearDown(controller.dispose);
      await expectLater(
        controller.initialize(),
        throwsA(
          isA<CaptureException>().having(
            (e) => e.reason,
            'reason',
            CaptureReason.registrationFailed,
          ),
        ),
      );
      expect(controller.state.value.status, CaptureStatus.unknown);
    },
  );

  test(
    'simultaneous owners cannot replace the default channel handler',
    () async {
      final listening = Completer<void>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(events, (call) async {
        calls.add(call.method);
        if (call.method == 'listen') listening.complete();
        return null;
      });
      final owner = FlutterScreenProtectionController();
      final duplicate = FlutterScreenProtectionController();
      addTearDown(owner.dispose);
      addTearDown(duplicate.dispose);
      final ready = owner.initialize();
      await listening.future;
      await expectLater(
        duplicate.initialize(),
        throwsA(
          isA<CaptureException>().having(
            (e) => e.reason,
            'reason',
            CaptureReason.ambiguousHost,
          ),
        ),
      );
      await deliver(codec.encodeSuccessEnvelope(packet('initial')));
      await ready;
      expect(owner.state.value.status, CaptureStatus.inactive);
      expect(duplicate.state.value.status, CaptureStatus.unknown);
      await owner.dispose();
      expect(calls, ['listen', 'cancel']);
    },
  );

  test('malformed envelopes invalidate a known state', () async {
    final listening = Completer<void>();
    messenger.setMockMethodCallHandler(events, (call) async {
      if (call.method == 'listen') listening.complete();
      return null;
    });
    final controller = FlutterScreenProtectionController();
    addTearDown(controller.dispose);
    final ready = controller.initialize();
    await listening.future;
    await deliver(codec.encodeSuccessEnvelope(packet('initial')));
    await ready;
    await deliver(ByteData(0));
    expect(controller.state.value.reason, CaptureReason.protocolFailure);
    expect(controller.state.value.status, CaptureStatus.unknown);
  });

  test('native stream end invalidates before cancellation completes', () async {
    final listening = Completer<void>();
    final cancelling = Completer<void>();
    final cancel = Completer<void>();
    messenger.setMockMethodCallHandler(events, (call) async {
      if (call.method == 'listen') listening.complete();
      if (call.method == 'cancel') {
        cancelling.complete();
        await cancel.future;
      }
      return null;
    });
    final controller = FlutterScreenProtectionController();
    addTearDown(() async {
      if (!cancel.isCompleted) cancel.complete();
      await controller.dispose();
    });
    final ready = controller.initialize();
    await listening.future;
    await deliver(codec.encodeSuccessEnvelope(packet('initial')));
    await ready;
    await deliver(null);
    await cancelling.future;
    expect(controller.state.value.reason, CaptureReason.transportFailure);
    expect(controller.state.value.status, CaptureStatus.unknown);
    cancel.complete();
    await controller.dispose();
  });

  test('a failed listen discards a buffered snapshot', () async {
    final listening = Completer<void>();
    final acknowledge = Completer<void>();
    messenger.setMockMethodCallHandler(events, (call) async {
      if (call.method == 'listen') {
        listening.complete();
        await acknowledge.future;
        throw PlatformException(
          code: 'registration',
          message: 'private details',
        );
      }
      return null;
    });
    final controller = FlutterScreenProtectionController();
    addTearDown(controller.dispose);
    final failed = expectLater(
      controller.initialize(),
      throwsA(
        isA<CaptureException>().having(
          (e) => e.reason,
          'reason',
          CaptureReason.registrationFailed,
        ),
      ),
    );
    await listening.future;
    await deliver(codec.encodeSuccessEnvelope(packet('initial')));
    acknowledge.complete();
    await failed;
    expect(controller.state.value.status, CaptureStatus.unknown);
  });

  test(
    'capability query uses MethodChannel and validates reply metadata',
    () async {
      Object? reply = {
        'version': 1,
        'capabilities': packet('unsupported')['capabilities'],
      };
      messenger.setMockMethodCallHandler(commands, (call) async {
        expect(call.method, 'getCaptureCapabilities');
        expect(call.arguments, {'version': 1});
        return reply;
      });
      const platform = ChannelCapturePlatform();
      final result = await platform.queryCapabilities();
      expect(result.screenshots.support, CaptureSupport.supported);
      expect(result.continuousCapture.reason, CaptureReason.unsupportedOs);
      reply = {'version': 2};
      await expectLater(
        platform.queryCapabilities(),
        throwsA(
          isA<CaptureException>().having(
            (e) => e.reason,
            'reason',
            CaptureReason.protocolFailure,
          ),
        ),
      );
    },
  );
}
