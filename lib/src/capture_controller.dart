import 'dart:async';

import 'package:flutter/foundation.dart';

import 'capture_models.dart';
import 'capture_platform.dart';
import 'capture_protocol.dart';

/// Own one instance at the root of each supported Flutter host.
final class FlutterScreenProtectionController {
  FlutterScreenProtectionController({
    CapturePlatform? platform,
    Duration initializationTimeout = const Duration(seconds: 10),
  }) : _platform = platform ?? const ChannelCapturePlatform(),
       _initializationTimeout = initializationTimeout {
    if (initializationTimeout <= Duration.zero) {
      throw ArgumentError('initializationTimeout must be positive');
    }
    _capabilities = _unavailable(CaptureReason.initializing);
  }

  final CapturePlatform _platform;
  final Duration _initializationTimeout;
  final _state = _CaptureStateListenable();
  final _events = StreamController<CaptureEvent>.broadcast();
  late CaptureCapabilities _capabilities;
  _Observation? _observation;
  int _latestSession = 0;
  Future<void> _cleanup = Future<void>.value();
  Future<void>? _disposal;

  ValueListenable<CaptureState> get state => _state;
  CaptureCapabilities get capabilities => _capabilities;
  Stream<CaptureEvent> get captureEvents => _events.stream;

  /// Completes on the first synchronized snapshot. Concurrent calls share
  /// that result. Call again after a failure to open a fresh session.
  Future<void> initialize() {
    if (_disposal != null) {
      return Future.error(const CaptureException(CaptureReason.disposed));
    }
    if (_observation case final current?) return current.ready.future;

    final observation = _Observation();
    _observation = observation;
    unawaited(_start(observation));
    return observation.ready.future;
  }

  Future<void> _start(_Observation observation) async {
    await _cleanup;
    if (_observation != observation) return;
    if (_platform.hostPlatform == CaptureHostPlatform.other) {
      _capabilities = unavailableCapabilities(
        CaptureHostPlatform.other,
        CaptureReason.unsupportedPlatform,
      );
      observation.ready.complete();
      _state.update((
        status: CaptureStatus.unsupported,
        scope: CaptureScope.unknown,
        reason: CaptureReason.unsupportedPlatform,
      ));
      return;
    }

    _invalidate(CaptureReason.initializing);
    if (_observation != observation) return;
    observation.timeout = Timer(_initializationTimeout, () {
      _fail(observation, CaptureReason.initializationTimeout);
    });
    try {
      observation.subscription = _platform.observeCapture().listen(
        (message) => _receive(observation, message),
        onError: (Object error, StackTrace _) => _fail(
          observation,
          error is CaptureException
              ? error.reason
              : CaptureReason.transportFailure,
        ),
        onDone: () => _fail(observation, CaptureReason.transportFailure),
      );
    } catch (_) {
      _fail(observation, CaptureReason.registrationFailed);
    }
  }

  void _receive(_Observation observation, Object? message) {
    if (_observation != observation) return;
    try {
      final (:session, :sequence) = CapturePacket.readHeader(message);
      final previousSession = observation.session;
      if (session < _latestSession ||
          (previousSession == 0 && session == _latestSession) ||
          (session == previousSession && sequence <= observation.sequence)) {
        return;
      }
      final packet = CapturePacket.decode(message);
      if (session > previousSession) {
        final snapshot = packet.state;
        final capabilities = packet.capabilities;
        if (snapshot == null ||
            capabilities?.platform != _platform.hostPlatform) {
          throw const CaptureException(CaptureReason.protocolFailure);
        }
        _latestSession = session;
        observation
          ..session = session
          ..sequence = sequence
          ..synchronized = true;
        observation.timeout?.cancel();
        _capabilities = capabilities!;
        if (!observation.ready.isCompleted) observation.ready.complete();
        _state.update(snapshot);
        return;
      }
      if (sequence != observation.sequence + 1 || !observation.synchronized) {
        throw const CaptureException(CaptureReason.protocolFailure);
      }
      observation.sequence = sequence;
      _apply(observation, packet.event!);
    } on CaptureException catch (error) {
      _fail(observation, error.reason);
    }
  }

  void _apply(_Observation observation, CaptureEvent event) {
    switch (event) {
      case ScreenshotTaken():
        final capability = _capabilities.screenshots;
        if (capability.support != CaptureSupport.supported ||
            capability.scope != event.scope) {
          throw const CaptureException(CaptureReason.protocolFailure);
        }
      case CaptureStateChanged():
        final previous = _state.value;
        if (_capabilities.continuousCapture.support !=
                CaptureSupport.supported ||
            previous.scope != event.scope ||
            (previous.status != CaptureStatus.active &&
                previous.status != CaptureStatus.inactive)) {
          throw const CaptureException(CaptureReason.protocolFailure);
        }
        if (previous.status == event.status) return;
        _state.update((status: event.status, scope: event.scope, reason: null));
      case CaptureStateInvalidated(:final reason):
        observation.synchronized = false;
        _invalidate(reason);
      case CaptureError(:final reason):
        _events.add(event);
        _fail(observation, reason);
        return;
    }
    if (_observation == observation) _events.add(event);
  }

  void _invalidate(CaptureReason reason) {
    _capabilities = _unavailable(reason);
    _state.update((
      status: CaptureStatus.unknown,
      scope: CaptureScope.unknown,
      reason: reason,
    ));
  }

  CaptureCapabilities _unavailable(CaptureReason reason) =>
      unavailableCapabilities(
        _platform.hostPlatform,
        reason,
        support: CaptureSupport.temporarilyUnavailable,
      );

  void _fail(_Observation observation, CaptureReason reason) {
    if (_observation != observation) return;
    _retire(observation, reason);
    _invalidate(reason);
  }

  void _retire(_Observation observation, CaptureReason reason) {
    _observation = null;
    observation.timeout?.cancel();
    if (!observation.ready.isCompleted) {
      observation.ready.completeError(CaptureException(reason));
    }
    // Fence old callbacks immediately and serialize cancellation before retry.
    _cleanup = _cleanup.then((_) async {
      try {
        await observation.subscription?.cancel();
      } catch (_) {
        // The failed subscription can no longer update the controller.
      }
    });
  }

  /// Terminal and idempotent. Consumer subscriptions receive a close signal.
  Future<void> dispose() {
    if (_disposal case final pending?) return pending;
    final completion = Completer<void>();
    _disposal = completion.future;
    if (_observation case final observation?) {
      _retire(observation, CaptureReason.disposed);
    }
    _invalidate(CaptureReason.disposed);
    // A paused app listener must not hold native resources or block teardown.
    unawaited(_events.close());
    unawaited(
      _cleanup.then((_) {
        _state.dispose();
        completion.complete();
      }),
    );
    return completion.future;
  }
}

final class _Observation {
  final ready = Completer<void>();
  StreamSubscription<Object?>? subscription;
  Timer? timeout;
  int session = 0;
  int sequence = -1;
  bool synchronized = false;
}

final class _CaptureStateListenable extends ChangeNotifier
    implements ValueListenable<CaptureState> {
  CaptureState _value = (
    status: CaptureStatus.unknown,
    scope: CaptureScope.unknown,
    reason: CaptureReason.initializing,
  );

  @override
  CaptureState get value => _value;

  void update(CaptureState next) {
    if (_value == next) return;
    _value = next;
    notifyListeners();
  }
}
