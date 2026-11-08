import 'dart:async';

import 'package:flutter_screen_protection/flutter_screen_protection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_capture_platform.dart';

Matcher captureFailure(CaptureReason reason) =>
    isA<CaptureException>().having((error) => error.reason, 'reason', reason);

void main() {
  late FakeCapturePlatform platform;
  late FlutterScreenProtectionController controller;

  void setUpController({
    CaptureHostPlatform host = CaptureHostPlatform.android,
  }) {
    platform = FakeCapturePlatform(hostPlatform: host);
    controller = FlutterScreenProtectionController(platform: platform);
    addTearDown(controller.dispose);
  }

  Future<void> initializeWith(String snapshot) async {
    final ready = controller.initialize();
    await Future<void>.value();
    platform.current.send(packet(snapshot));
    await ready;
  }

  test(
    'starts unknown and shares initialization through the active session',
    () async {
      setUpController();
      expect(controller.state.value.status, CaptureStatus.unknown);
      final ready = controller.initialize();
      expect(controller.initialize(), same(ready));
      await Future<void>.value();
      expect(platform.sessions, hasLength(1));
      expect(controller.state.value.status, CaptureStatus.unknown);
      platform.current.send(packet('initialActive'));
      await ready;
      expect(controller.initialize(), same(ready));
      expect(platform.sessions, hasLength(1));
      expect(controller.state.value.status, CaptureStatus.active);
      expect(controller.capabilities.continuousCapture.scope, CaptureScope.uid);
    },
  );

  test(
    'broadcasts confirmed events to two listeners and retains current state',
    () async {
      setUpController();
      final statuses = <CaptureStatus>[];
      controller.state.addListener(
        () => statuses.add(controller.state.value.status),
      );
      final first = controller.captureEvents.take(3).toList();
      final second = controller.captureEvents.take(3).toList();
      await initializeWith('initial');
      platform.current.send(packet('screenshot'));
      expect(controller.state.value.status, CaptureStatus.inactive);
      platform.current.send(packet('started'));
      platform.current.send(packet('stopped'));
      final events = await first;
      expect(await second, events);
      expect(events, [
        isA<ScreenshotTaken>(),
        isA<CaptureStateChanged>().having(
          (e) => e.status,
          'status',
          CaptureStatus.active,
        ),
        isA<CaptureStateChanged>().having(
          (e) => e.status,
          'status',
          CaptureStatus.inactive,
        ),
      ]);
      expect(statuses, [
        CaptureStatus.inactive,
        CaptureStatus.active,
        CaptureStatus.inactive,
      ]);
      expect(controller.state.value.status, CaptureStatus.inactive);
      expect(platform.current.cancellationCount, 0);
      final lateEvent = controller.captureEvents.first;
      platform.current.send({...packet('screenshot'), 'sequence': 4});
      expect((await lateEvent).sequence, 4);
    },
  );

  test(
    'ignores duplicate and late packets and suppresses unchanged status',
    () async {
      setUpController();
      await initializeWith('initial');
      final events = controller.captureEvents.take(2).toList();
      var updates = 0;
      controller.state.addListener(() => updates++);
      platform.current.send(packet('screenshot'));
      platform.current.send(packet('started'));
      platform.current.send(packet('screenshot'));
      platform.current.send({...packet('started'), 'kind': 'invalid'});
      platform.current.send({...packet('started'), 'sequence': 3});
      expect((await events).map((e) => e.sequence), [1, 2]);
      expect(updates, 1);
      expect(controller.state.value.status, CaptureStatus.active);
    },
  );

  test(
    'invalidation requires a new snapshot and drops obsolete generations',
    () async {
      setUpController();
      await initializeWith('initial');
      final events = controller.captureEvents.take(3).toList();
      platform.current.send(packet('screenshot'));
      platform.current.send(packet('started'));
      platform.current.send({...packet('invalidated'), 'sequence': 3});
      expect(controller.state.value.status, CaptureStatus.unknown);
      expect(controller.state.value.reason, CaptureReason.backgrounded);
      expect(
        controller.capabilities.screenshots.support,
        CaptureSupport.temporarilyUnavailable,
      );
      expect((await events).last, isA<CaptureStateInvalidated>());
      platform.current.send(packet('resumed'));
      platform.current.send(packet('stopped'));
      expect(controller.state.value.status, CaptureStatus.active);
      expect(platform.sessions, hasLength(1));
    },
  );

  test('same-session changes after invalidation fail closed', () async {
    setUpController();
    await initializeWith('initial');
    platform.current.send({...packet('invalidated'), 'sequence': 1});
    platform.current.send(packet('started'));
    expect(controller.state.value.reason, CaptureReason.protocolFailure);
    expect(controller.state.value.status, CaptureStatus.unknown);
  });

  test(
    'gaps fail closed and retry waits for cancellation and fresh generation',
    () async {
      setUpController();
      final gate = Completer<void>();
      platform.cancellationGate = gate.future;
      await initializeWith('initial');
      final oldSession = platform.current;
      oldSession.send(packet('started'));
      expect(controller.state.value.reason, CaptureReason.protocolFailure);
      final ready = controller.initialize();
      oldSession.send(packet('screenshot'));
      await Future<void>.value();
      expect(platform.sessions, hasLength(1));
      expect(oldSession.cancellationCount, 1);
      expect(controller.state.value.status, CaptureStatus.unknown);
      gate.complete();
      // Wait for the queued teardown and retry to finish their microtasks.
      await pumpEventQueue(times: 1);
      expect(platform.sessions, hasLength(2));
      platform.current.send(packet('initial'));
      platform.current.send(packet('started'));
      expect(controller.state.value.status, CaptureStatus.unknown);
      platform.current.send(packet('resumed'));
      await ready;
      expect(controller.state.value.status, CaptureStatus.active);
    },
  );

  for (final invalid in [
    packet('screenshot'),
    {'version': 99},
    null,
  ]) {
    test(
      'invalid first packet fails initialization and leaves unknown ($invalid)',
      () async {
        setUpController();
        final ready = controller.initialize();
        final failure = expectLater(
          ready,
          throwsA(captureFailure(CaptureReason.protocolFailure)),
        );
        await Future<void>.value();
        platform.current.send(invalid);
        await failure;
        expect(controller.state.value.status, CaptureStatus.unknown);
        expect(controller.state.value.reason, CaptureReason.protocolFailure);
      },
    );
  }

  test('unsupported recording retains screenshot capability', () async {
    setUpController();
    await initializeWith('unsupported');
    final screenshot = controller.captureEvents.first;
    platform.current.send(packet('screenshot'));
    expect(await screenshot, isA<ScreenshotTaken>());
    expect(controller.state.value.status, CaptureStatus.unsupported);
    expect(controller.state.value.reason, CaptureReason.unsupportedOs);
  });

  test('unsupported host is explicit and never opens a stream', () async {
    setUpController(host: CaptureHostPlatform.other);
    await controller.initialize();
    expect(controller.state.value.status, CaptureStatus.unsupported);
    expect(
      controller.capabilities.screenshots.reason,
      CaptureReason.unsupportedPlatform,
    );
    expect(platform.sessions, isEmpty);
  });

  test('ambiguous iOS host stays unknown', () async {
    setUpController(host: CaptureHostPlatform.ios);
    await initializeWith('unknown');
    expect(controller.state.value.status, CaptureStatus.unknown);
    expect(controller.state.value.reason, CaptureReason.ambiguousHost);
  });

  test(
    'native error event is typed and recoverable without closing broadcast',
    () async {
      setUpController();
      await initializeWith('resumed');
      final events = controller.captureEvents.take(2).toList();
      platform.current.send(packet('error'));
      expect(controller.state.value.reason, CaptureReason.registrationFailed);
      final ready = controller.initialize();
      await pumpEventQueue(times: 1);
      platform.current.send({...packet('initial'), 'session': 3});
      await ready;
      platform.current.send({...packet('screenshot'), 'session': 3});
      expect(await events, [isA<CaptureError>(), isA<ScreenshotTaken>()]);
    },
  );

  test(
    'stream errors redact details and can retry initial synchronization',
    () async {
      setUpController();
      final ready = controller.initialize();
      final failure = expectLater(
        ready,
        throwsA(captureFailure(CaptureReason.transportFailure)),
      );
      await Future<void>.value();
      platform.current.fail(StateError('sensitive native message'));
      await failure;
      expect(controller.state.value.reason, CaptureReason.transportFailure);
      final retry = controller.initialize();
      await pumpEventQueue(times: 1);
      platform.current.send(packet('initial'));
      await retry;
      expect(controller.state.value.status, CaptureStatus.inactive);
    },
  );

  test(
    'stream interruption clears a previously known inactive state',
    () async {
      setUpController();
      await initializeWith('initial');
      await platform.current.interrupt();
      expect(controller.state.value.status, CaptureStatus.unknown);
      expect(controller.state.value.reason, CaptureReason.transportFailure);
    },
  );

  test(
    'disposal while initializing is terminal and releases the stream once',
    () async {
      setUpController();
      final ready = controller.initialize();
      final failure = expectLater(
        ready,
        throwsA(captureFailure(CaptureReason.disposed)),
      );
      await Future<void>.value();
      final done = controller.captureEvents.drain<void>();
      final disposed = controller.dispose();
      expect(controller.dispose(), same(disposed));
      await failure;
      await disposed;
      await done;
      expect(platform.current.cancellationCount, 1);
      expect(controller.state.value.reason, CaptureReason.disposed);
      await expectLater(
        controller.initialize(),
        throwsA(captureFailure(CaptureReason.disposed)),
      );
    },
  );

  test(
    'paused listeners and disposal during state notification are safe',
    () async {
      setUpController();
      final listener = controller.captureEvents.listen((_) {})..pause();
      addTearDown(listener.cancel);
      controller.state.addListener(() {
        if (controller.state.value.status == CaptureStatus.active) {
          unawaited(controller.dispose());
        }
      });
      await initializeWith('initialActive');
      await controller.dispose();
      expect(platform.current.cancellationCount, 1);
      expect(controller.state.value.reason, CaptureReason.disposed);
    },
  );

  testWidgets('snapshot timeout is deterministic and leaves state unknown', (
    tester,
  ) async {
    platform = FakeCapturePlatform();
    controller = FlutterScreenProtectionController(
      platform: platform,
      initializationTimeout: const Duration(seconds: 1),
    );
    final failure = expectLater(
      controller.initialize(),
      throwsA(captureFailure(CaptureReason.initializationTimeout)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await failure;
    expect(controller.state.value.status, CaptureStatus.unknown);
    expect(platform.current.cancellationCount, 1);
    await controller.dispose();
  });
}
