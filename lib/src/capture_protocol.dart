import 'capture_models.dart';

const captureProtocolVersion = 1;

enum CapturePacketKind {
  snapshot,
  screenshotTaken,
  captureStarted,
  captureStopped,
  invalidated,
  error,
}

typedef CaptureHeader = ({int session, int sequence});

/// Internal v1 codec shared by channel consumers and fixture tests.
final class CapturePacket {
  const CapturePacket._({
    required this.kind,
    required this.header,
    required this.observedAt,
    required this.scope,
    this.state,
    this.capabilities,
    this.event,
  });

  final CapturePacketKind kind;
  final CaptureHeader header;
  final DateTime observedAt;
  final CaptureScope scope;
  final CaptureState? state;
  final CaptureCapabilities? capabilities;
  final CaptureEvent? event;

  static CaptureHeader readHeader(Object? message) {
    final map = _map(message);
    if (map['version'] is! int || map['version'] != captureProtocolVersion) {
      _invalid();
    }
    return (
      session: _integer(map['session'], min: 1),
      sequence: _integer(map['sequence']),
    );
  }

  factory CapturePacket.decode(Object? message) {
    final header = readHeader(message);
    final map = _map(message);
    final kind = _enum(CapturePacketKind.values, map['kind']);
    final scope = _enum(CaptureScope.values, map['scope']);
    final observedAt = DateTime.fromMillisecondsSinceEpoch(
      _integer(map['timestampMs'], max: 8640000000000000),
      isUtc: true,
    );
    final (:session, :sequence) = header;
    CaptureState? state;
    CaptureCapabilities? capabilities;
    CaptureEvent? event;
    switch (kind) {
      case CapturePacketKind.snapshot:
        if (sequence != 0) _invalid();
        final status = _enum(CaptureStatus.values, map['status']);
        final reason = _reason(map['reason']);
        final known =
            status == CaptureStatus.active || status == CaptureStatus.inactive;
        if (known != (reason == null)) _invalid();
        capabilities = decodeCapabilities(map['capabilities']);
        final continuous = capabilities.continuousCapture;
        if (scope != continuous.scope ||
            (known && continuous.support != CaptureSupport.supported) ||
            (status == CaptureStatus.unsupported &&
                (continuous.support != CaptureSupport.unavailable ||
                    reason != continuous.reason))) {
          _invalid();
        }
        state = (status: status, scope: scope, reason: reason);
      case CapturePacketKind.screenshotTaken:
        if (scope == CaptureScope.unknown) _invalid();
        event = ScreenshotTaken(
          session: session,
          sequence: sequence,
          observedAt: observedAt,
          scope: scope,
        );
      case CapturePacketKind.captureStarted:
      case CapturePacketKind.captureStopped:
        if (scope == CaptureScope.unknown) _invalid();
        event = CaptureStateChanged(
          session: session,
          sequence: sequence,
          observedAt: observedAt,
          scope: scope,
          status: kind == CapturePacketKind.captureStarted
              ? CaptureStatus.active
              : CaptureStatus.inactive,
        );
      case CapturePacketKind.invalidated:
        event = CaptureStateInvalidated(
          session: session,
          sequence: sequence,
          observedAt: observedAt,
          scope: scope,
          reason: _enum(CaptureReason.values, map['reason']),
        );
      case CapturePacketKind.error:
        event = CaptureError(
          session: session,
          sequence: sequence,
          observedAt: observedAt,
          scope: scope,
          reason: _enum(CaptureReason.values, map['reason']),
        );
    }
    if (event != null && sequence == 0) _invalid();
    return CapturePacket._(
      kind: kind,
      header: header,
      observedAt: observedAt,
      scope: scope,
      state: state,
      capabilities: capabilities,
      event: event,
    );
  }

  Map<String, Object?> encode() => {
    'version': captureProtocolVersion,
    'session': header.session,
    'sequence': header.sequence,
    'kind': kind.name,
    'timestampMs': observedAt.millisecondsSinceEpoch,
    'scope': scope.name,
    if (state case final snapshot?) ...{
      'status': snapshot.status.name,
      if (snapshot.reason case final reason?) 'reason': reason.name,
      'capabilities': encodeCapabilities(capabilities!),
    },
    if (event case CaptureStateInvalidated(:final reason))
      'reason': reason.name,
    if (event case CaptureError(:final reason)) 'reason': reason.name,
  };
}

CaptureCapabilities decodeCapabilities(Object? value) {
  final map = _map(value);
  final platform = _enum(CaptureHostPlatform.values, map['platform']);
  final screenshots = _capability(map['screenshots']);
  final continuous = _capability(map['continuousCapture']);
  if (screenshots.support == CaptureSupport.supported &&
      screenshots.scope !=
          switch (platform) {
            CaptureHostPlatform.android => CaptureScope.activity,
            CaptureHostPlatform.ios => CaptureScope.application,
            CaptureHostPlatform.other => CaptureScope.unknown,
          }) {
    _invalid();
  }
  if (continuous.support == CaptureSupport.supported &&
      !(switch (platform) {
        CaptureHostPlatform.android => continuous.scope == CaptureScope.uid,
        CaptureHostPlatform.ios =>
          continuous.scope == CaptureScope.scene ||
              continuous.scope == CaptureScope.screen,
        CaptureHostPlatform.other => false,
      })) {
    _invalid();
  }
  return (
    platform: platform,
    screenshots: screenshots,
    continuousCapture: continuous,
  );
}

Map<String, Object?> encodeCapabilities(CaptureCapabilities capabilities) => {
  'platform': capabilities.platform.name,
  'screenshots': _encodeCapability(capabilities.screenshots),
  'continuousCapture': _encodeCapability(capabilities.continuousCapture),
};

Map<String, Object?> _encodeCapability(CaptureCapability capability) => {
  'support': capability.support.name,
  'scope': capability.scope.name,
  if (capability.reason case final reason?) 'reason': reason.name,
};

CaptureCapability _capability(Object? value) {
  final map = _map(value);
  final support = _enum(CaptureSupport.values, map['support']);
  final scope = _enum(CaptureScope.values, map['scope']);
  final reason = _reason(map['reason']);
  if (support == CaptureSupport.supported
      ? reason != null || scope == CaptureScope.unknown
      : reason == null) {
    _invalid();
  }
  return (support: support, scope: scope, reason: reason);
}

Map<Object?, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) _invalid();
  return value;
}

int _integer(Object? value, {int min = 0, int max = 9007199254740991}) {
  if (value is! int || value < min || value > max) _invalid();
  return value;
}

T _enum<T extends Enum>(List<T> values, Object? value) {
  if (value is String) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
  }
  _invalid();
}

CaptureReason? _reason(Object? value) =>
    value == null ? null : _enum(CaptureReason.values, value);

Never _invalid() => throw const CaptureException(CaptureReason.protocolFailure);
