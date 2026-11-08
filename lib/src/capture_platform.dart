import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'capture_models.dart';
import 'capture_protocol.dart';

/// Platform seam for the capture protocol. Each subscription starts a fresh
/// observation session and cancellation releases that session.
abstract interface class CapturePlatform {
  CaptureHostPlatform get hostPlatform;

  Stream<Object?> observeCapture();
}

/// Uses EventChannel's wire format with an explicit listen/cancel handshake.
/// Flutter's standard receiver reports handshake errors to FlutterError
/// instead of delivering them to the subscriber.
final class ChannelCapturePlatform implements CapturePlatform {
  const ChannelCapturePlatform();

  static const _events = EventChannel('flutter_screen_protection/events');
  static const _eventControl = MethodChannel(
    'flutter_screen_protection/events',
  );
  static const _commands = MethodChannel('flutter_screen_protection');
  static const _arguments = {'version': captureProtocolVersion};
  static const _cancelTimeout = Duration(seconds: 5);
  static bool _observing = false;

  @override
  CaptureHostPlatform get hostPlatform => kIsWeb
      ? CaptureHostPlatform.other
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => CaptureHostPlatform.android,
          TargetPlatform.iOS => CaptureHostPlatform.ios,
          _ => CaptureHostPlatform.other,
        };

  /// Out-of-band query for diagnostics. The controller only uses the
  /// capabilities that arrived with its ordered EventChannel snapshot.
  Future<CaptureCapabilities> queryCapabilities() async {
    if (hostPlatform == CaptureHostPlatform.other) {
      return unavailableCapabilities(
        hostPlatform,
        CaptureReason.unsupportedPlatform,
      );
    }
    try {
      final reply = await _commands.invokeMethod<Object?>(
        'getCaptureCapabilities',
        _arguments,
      );
      if (reply is! Map ||
          reply['version'] is! int ||
          reply['version'] != captureProtocolVersion) {
        throw const CaptureException(CaptureReason.protocolFailure);
      }
      final capabilities = decodeCapabilities(reply['capabilities']);
      if (capabilities.platform != hostPlatform) {
        throw const CaptureException(CaptureReason.protocolFailure);
      }
      return capabilities;
    } on CaptureException {
      rethrow;
    } on MissingPluginException {
      throw const CaptureException(CaptureReason.registrationFailed);
    } catch (_) {
      throw const CaptureException(CaptureReason.transportFailure);
    }
  }

  @override
  Stream<Object?> observeCapture() {
    late final StreamController<Object?> stream;
    var ownsChannel = false;
    var accepting = true;
    var acknowledged = false;
    final pending = <Object?>[];

    Future<void> listen() async {
      if (_observing) {
        stream.addError(const CaptureException(CaptureReason.ambiguousHost));
        unawaited(stream.close());
        return;
      }
      try {
        final messenger = _events.binaryMessenger;
        _observing = ownsChannel = true;
        messenger.setMessageHandler(_events.name, (reply) async {
          if (!accepting || stream.isClosed) return null;
          if (reply == null) {
            // Stream done can wait for asynchronous cancel. Publish failure
            // first so previously known capture state is cleared immediately.
            stream.addError(
              CaptureException(
                acknowledged
                    ? CaptureReason.transportFailure
                    : CaptureReason.registrationFailed,
              ),
            );
            unawaited(stream.close());
          } else {
            try {
              final packet = _events.codec.decodeEnvelope(reply);
              if (acknowledged) {
                stream.add(packet);
              } else if (pending.length < 64) {
                pending.add(packet);
              } else {
                stream.addError(
                  const CaptureException(CaptureReason.protocolFailure),
                );
                unawaited(stream.close());
              }
            } on PlatformException {
              stream.addError(
                const CaptureException(CaptureReason.transportFailure),
              );
            } catch (_) {
              stream.addError(
                const CaptureException(CaptureReason.protocolFailure),
              );
            }
          }
          return null;
        });
        await _eventControl.invokeMethod<void>('listen', _arguments);
        if (!accepting || stream.isClosed) return;
        acknowledged = true;
        for (final packet in pending) {
          stream.add(packet);
        }
        pending.clear();
      } catch (_) {
        if (accepting && !stream.isClosed) {
          stream.addError(
            const CaptureException(CaptureReason.registrationFailed),
          );
          unawaited(stream.close());
        }
      }
    }

    Future<void> cancel() async {
      accepting = false;
      pending.clear();
      if (!ownsChannel) return;
      try {
        _events.binaryMessenger.setMessageHandler(_events.name, null);
        await _eventControl
            .invokeMethod<void>('cancel', _arguments)
            .timeout(_cancelTimeout);
      } catch (_) {
        // Local ownership is already fenced. Native teardown is also tied
        // to host lifecycle, and a subsequent listen replaces old observers.
      } finally {
        _observing = ownsChannel = false;
        if (!stream.isClosed) unawaited(stream.close());
      }
    }

    stream = StreamController<Object?>(onListen: listen, onCancel: cancel);
    return stream.stream;
  }
}

CaptureCapabilities unavailableCapabilities(
  CaptureHostPlatform platform,
  CaptureReason reason, {
  CaptureSupport support = CaptureSupport.unavailable,
}) {
  final capability = (
    support: support,
    scope: CaptureScope.unknown,
    reason: reason,
  );
  return (
    platform: platform,
    screenshots: capability,
    continuousCapture: capability,
  );
}
