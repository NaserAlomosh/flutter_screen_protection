import 'package:flutter/widgets.dart';

/// The latest observation of continuous capture for the reported scope.
enum CaptureStatus { unknown, active, inactive, unsupported }

enum CaptureScope { unknown, activity, uid, application, scene, screen }

enum CaptureHostPlatform { android, ios, other }

enum CaptureSupport { supported, unavailable, temporarilyUnavailable }

/// Stable metadata codes. Platform exception text is never exposed.
enum CaptureReason {
  initializing,
  backgrounded,
  detached,
  ambiguousHost,
  unsupportedPlatform,
  unsupportedOs,
  permissionMissing,
  registrationFailed,
  transportFailure,
  protocolFailure,
  initializationTimeout,
  disposed,
}

enum SensitiveProtection { mask, blur, replace }

/// The policy to apply when capture state is unknown or unsupported.
enum UnknownCaptureBehavior { mask, reveal }

/// Rendering options for the future SensitiveContent widget.
final class SensitiveProtectionConfiguration {
  SensitiveProtectionConfiguration({
    this.protection = SensitiveProtection.mask,
    this.unknownBehavior = UnknownCaptureBehavior.mask,
    this.alwaysProtect = false,
    this.blurSigma = 12,
    this.replacement,
  }) {
    if (!blurSigma.isFinite || blurSigma <= 0) {
      throw ArgumentError('blurSigma must be finite and positive');
    }
    if (protection == SensitiveProtection.replace && replacement == null) {
      throw ArgumentError('replace mode requires replacement content');
    }
  }

  final SensitiveProtection protection;
  final UnknownCaptureBehavior unknownBehavior;
  final bool alwaysProtect;
  final double blurSigma;

  /// App-owned safe content. This value never crosses the native channel.
  final Widget? replacement;
}

typedef CaptureState = ({
  CaptureStatus status,
  CaptureScope scope,
  CaptureReason? reason,
});

typedef CaptureCapability = ({
  CaptureSupport support,
  CaptureScope scope,
  CaptureReason? reason,
});

typedef CaptureCapabilities = ({
  CaptureHostPlatform platform,
  CaptureCapability screenshots,
  CaptureCapability continuousCapture,
});

sealed class CaptureEvent {
  const CaptureEvent({
    required this.session,
    required this.sequence,
    required this.observedAt,
    required this.scope,
  });

  final int session;
  final int sequence;
  final DateTime observedAt;
  final CaptureScope scope;
}

final class ScreenshotTaken extends CaptureEvent {
  const ScreenshotTaken({
    required super.session,
    required super.sequence,
    required super.observedAt,
    required super.scope,
  });
}

/// A confirmed transition within a synchronized native binding.
final class CaptureStateChanged extends CaptureEvent {
  const CaptureStateChanged({
    required super.session,
    required super.sequence,
    required super.observedAt,
    required super.scope,
    required this.status,
  });

  final CaptureStatus status;
}

final class CaptureStateInvalidated extends CaptureEvent {
  const CaptureStateInvalidated({
    required super.session,
    required super.sequence,
    required super.observedAt,
    required super.scope,
    required this.reason,
  });

  final CaptureReason reason;
}

final class CaptureError extends CaptureEvent {
  const CaptureError({
    required super.session,
    required super.sequence,
    required super.observedAt,
    required super.scope,
    required this.reason,
  });

  final CaptureReason reason;
}

final class CaptureException implements Exception {
  const CaptureException(this.reason);

  final CaptureReason reason;

  @override
  String toString() => 'CaptureException(${reason.name})';
}
