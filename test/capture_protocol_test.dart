import 'package:flutter/widgets.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';
import 'package:flutter_screen_protection/src/capture_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_capture_platform.dart';

void main() {
  for (final name in packetNames) {
    test('v1 fixture $name round-trips with UTC timestamps', () {
      final wire = packet(name);
      final decoded = CapturePacket.decode(wire);
      expect(decoded.encode(), wire);
      expect(decoded.observedAt.isUtc, isTrue);
      expect(
        decoded.event?.observedAt ?? decoded.observedAt,
        decoded.observedAt,
      );
    });
  }

  test('decodes typed event variants and independent capabilities', () {
    expect(
      CapturePacket.decode(packet('screenshot')).event,
      isA<ScreenshotTaken>(),
    );
    expect(
      CapturePacket.decode(packet('started')).event,
      isA<CaptureStateChanged>().having(
        (event) => event.status,
        'status',
        CaptureStatus.active,
      ),
    );
    expect(
      CapturePacket.decode(packet('stopped')).event,
      isA<CaptureStateChanged>().having(
        (event) => event.status,
        'status',
        CaptureStatus.inactive,
      ),
    );
    expect(
      CapturePacket.decode(packet('invalidated')).event,
      isA<CaptureStateInvalidated>(),
    );
    expect(CapturePacket.decode(packet('error')).event, isA<CaptureError>());
    final unsupported = CapturePacket.decode(packet('unsupported'));
    expect(unsupported.state?.status, CaptureStatus.unsupported);
    expect(
      unsupported.capabilities?.screenshots.support,
      CaptureSupport.supported,
    );
    expect(
      unsupported.capabilities?.continuousCapture.support,
      CaptureSupport.unavailable,
    );
    expect(
      CapturePacket.decode(packet('unknown')).state?.status,
      CaptureStatus.unknown,
    );
  });

  final invalidPackets = <Object?>[
    null,
    [],
    {...packet('initial'), 42: 'bad key'},
    {...packet('initial'), 'version': 2},
    {...packet('initial'), 'version': 1.0},
    {...packet('initial'), 'sequence': 1},
    {...packet('screenshot'), 'sequence': -1},
    {...packet('screenshot'), 'sequence': 0},
    {...packet('screenshot'), 'sequence': 9007199254740992},
    {...packet('screenshot'), 'session': '1'},
    {...packet('screenshot'), 'session': 0},
    {...packet('screenshot'), 'timestampMs': 8640000000000001},
    {...packet('screenshot'), 'scope': 'unknown'},
    {...packet('screenshot'), 'kind': 'unrecognized'},
    {...packet('initial'), 'scope': 'scene'},
    {...packet('initial'), 'status': 'unknown'},
    {...packet('initial'), 'reason': 'detached'},
    {...packet('initial'), 'capabilities': {}},
    {...packet('unsupported'), 'status': 'inactive', 'reason': null},
    {...packet('unsupported'), 'reason': 'unsupportedPlatform'},
    {...packet('invalidated')}..remove('reason'),
    {...packet('error'), 'reason': 'arbitrary exception text'},
  ];
  for (final (index, wire) in invalidPackets.indexed) {
    test('rejects malformed wire case $index with a safe reason', () {
      expect(
        () => CapturePacket.decode(wire),
        throwsA(
          isA<CaptureException>().having(
            (error) => error.reason,
            'reason',
            CaptureReason.protocolFailure,
          ),
        ),
      );
    });
  }

  test('additive fields are ignored', () {
    final wire = {...packet('initial'), 'futureField': true};
    expect(CapturePacket.decode(wire).encode(), packet('initial'));
  });

  test('protection configuration defaults to masking and validates inputs', () {
    final defaults = SensitiveProtectionConfiguration();
    expect(defaults.protection, SensitiveProtection.mask);
    expect(defaults.unknownBehavior, UnknownCaptureBehavior.mask);
    expect(defaults.alwaysProtect, isFalse);
    for (final sigma in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => SensitiveProtectionConfiguration(blurSigma: sigma),
        throwsArgumentError,
      );
    }
    expect(
      () => SensitiveProtectionConfiguration(
        protection: SensitiveProtection.replace,
      ),
      throwsArgumentError,
    );
    const replacement = SizedBox();
    final custom = SensitiveProtectionConfiguration(
      protection: SensitiveProtection.replace,
      unknownBehavior: UnknownCaptureBehavior.reveal,
      replacement: replacement,
    );
    expect(custom.replacement, same(replacement));
    expect(custom.unknownBehavior, UnknownCaptureBehavior.reveal);
  });
}
