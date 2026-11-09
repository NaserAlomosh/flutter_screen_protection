import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';
import 'package:flutter_screen_protection_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('flutter_screen_protection');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (_) async => 'Android 16');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, null);
  });

  testWidgets('initializes once and counts each accepted screenshot', (
    tester,
  ) async {
    final platform = _AndroidCapture();
    await tester.pumpWidget(MyApp(capturePlatform: platform));
    expect(find.text('Plugin: Initializing…'), findsOneWidget);

    platform.snapshot();
    await tester.pumpAndSettle();
    expect(find.text('Platform: Android 16'), findsOneWidget);
    expect(find.text('Plugin: Initialized'), findsOneWidget);
    expect(
      find.text('Screenshot detection: Supported · activity'),
      findsOneWidget,
    );

    platform.screenshot(1);
    await tester.pumpAndSettle();
    expect(find.text('Screenshots detected: 1'), findsOneWidget);
    expect(find.textContaining('Last screenshot time: 2023-'), findsOneWidget);
    expect(
      find.text('Last screenshot event: Session 1, sequence 1 · activity'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Screenshot detected ·'),
      100,
    );
    expect(find.textContaining('Screenshot detected ·'), findsOneWidget);

    await tester.pumpWidget(MyApp(capturePlatform: platform));
    platform.screenshot(1);
    platform.screenshot(2);
    platform.screenshot(2);
    platform.screenshot(3);
    await tester.pumpAndSettle();
    expect(find.text('Screenshots detected: 3'), findsOneWidget);
    expect(platform.listens, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(platform.cancels, 1);
    platform.screenshot(4);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows unsupported capability after successful initialization', (
    tester,
  ) async {
    final platform = _AndroidCapture();
    await tester.pumpWidget(MyApp(capturePlatform: platform));
    platform.snapshot(supported: false);
    await tester.pumpAndSettle();
    expect(find.text('Plugin: Initialized'), findsOneWidget);
    expect(
      find.text('Screenshot detection: Unsupported · unsupportedOs'),
      findsOneWidget,
    );
    expect(find.text('Continuous capture: unsupported'), findsOneWidget);
  });

  testWidgets('shows a transport failure during initialization', (
    tester,
  ) async {
    final platform = _AndroidCapture();
    await tester.pumpWidget(MyApp(capturePlatform: platform));
    platform.packets.addError(
      const CaptureException(CaptureReason.transportFailure),
    );
    await tester.pumpAndSettle();
    expect(find.text('Plugin: Initialization failed'), findsOneWidget);
    expect(find.text('Last error: transportFailure'), findsOneWidget);
    expect(
      find.textContaining('Capture observation error · transportFailure'),
      findsOneWidget,
    );
    expect(platform.cancels, 1);
  });

  testWidgets('shows a protocol failure after initialization', (tester) async {
    final platform = _AndroidCapture();
    await tester.pumpWidget(MyApp(capturePlatform: platform));
    platform.snapshot();
    platform.screenshot(2); // Sequence 1 is missing.
    await tester.pumpAndSettle();
    expect(find.text('Screenshots detected: 0'), findsOneWidget);
    expect(find.text('Last error: protocolFailure'), findsOneWidget);
    expect(platform.cancels, 1);
  });

  testWidgets('disposes while both initialization requests are pending', (
    tester,
  ) async {
    final platform = _AndroidCapture();
    final version = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (_) => version.future);
    await tester.pumpWidget(MyApp(capturePlatform: platform));
    expect(platform.listens, 1);
    await tester.pumpWidget(const SizedBox());
    version.complete('Android 16');
    platform.snapshot();
    await tester.pumpAndSettle();
    expect(platform.cancels, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resynchronizes after lifecycle invalidation on one stream', (
    tester,
  ) async {
    final platform = _AndroidCapture();
    await tester.pumpWidget(MyApp(capturePlatform: platform));
    platform.snapshot();
    platform.screenshot(1);
    await tester.pumpAndSettle();

    platform.emit('invalidated', 2, fields: {'reason': 'backgrounded'});
    await tester.pumpAndSettle();
    expect(
      find.text('Screenshot detection: Temporarily unavailable · backgrounded'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Session invalidated · backgrounded'),
      100,
    );

    platform.snapshot(session: 2);
    platform.screenshot(3); // Late packet from the retired session.
    platform.screenshot(1, session: 2);
    await tester.pumpAndSettle();
    expect(
      find.text('Screenshot detection: Supported · activity'),
      findsOneWidget,
    );
    expect(find.text('Screenshots detected: 2'), findsOneWidget);
    expect(
      find.text('Last screenshot event: Session 2, sequence 1 · activity'),
      findsOneWidget,
    );
    expect(platform.listens, 1);
  });
}

class _AndroidCapture implements CapturePlatform {
  int listens = 0;
  int cancels = 0;
  late final packets = StreamController<Object?>.broadcast(
    onListen: () => listens++,
    onCancel: () => cancels++,
  );

  @override
  CaptureHostPlatform get hostPlatform => CaptureHostPlatform.android;

  @override
  Stream<Object?> observeCapture() => packets.stream;

  void snapshot({int session = 1, bool supported = true}) {
    const unsupported = {
      'support': 'unavailable',
      'scope': 'unknown',
      'reason': 'unsupportedOs',
    };
    emit(
      'snapshot',
      0,
      session: session,
      fields: {
        'status': 'unsupported',
        'reason': 'unsupportedOs',
        'capabilities': {
          'platform': 'android',
          'screenshots': supported
              ? {'support': 'supported', 'scope': 'activity'}
              : unsupported,
          'continuousCapture': unsupported,
        },
      },
    );
  }

  void screenshot(int sequence, {int session = 1}) =>
      emit('screenshotTaken', sequence, session: session, scope: 'activity');

  void emit(
    String kind,
    int sequence, {
    int session = 1,
    String scope = 'unknown',
    Map<String, Object> fields = const {},
  }) {
    packets.add({
      'version': 1,
      'kind': kind,
      'session': session,
      'sequence': sequence,
      'timestampMs': 1700000000000 + sequence,
      'scope': scope,
      ...fields,
    });
  }
}
