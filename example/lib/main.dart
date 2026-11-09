import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.capturePlatform});

  final CapturePlatform? capturePlatform;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const _historyLimit = 30;

  late final FlutterScreenProtectionController _controller;
  late final StreamSubscription<CaptureEvent> _events;
  final _history = <String>[];
  String _platformVersion = 'Loading…';
  String _initialization = 'Initializing…';
  String? _error;
  int _screenshotCount = 0;
  ScreenshotTaken? _lastScreenshot;
  CaptureEvent? _lastEvent;
  DateTime? _lastStateUpdate;
  CaptureStatus _previousStatus = CaptureStatus.unknown;

  @override
  void initState() {
    super.initState();
    _controller = FlutterScreenProtectionController(
      platform: widget.capturePlatform,
    );
    _controller.state.addListener(_onStateChanged);
    _events = _controller.captureEvents.listen(_onEvent);
    unawaited(_loadPlatformVersion());
    unawaited(_initialize());
  }

  Future<void> _loadPlatformVersion() async {
    try {
      final version = await FlutterScreenProtection().getPlatformVersion();
      if (!mounted) return;
      setState(() => _platformVersion = version ?? 'Unknown');
    } catch (_) {
      if (!mounted) return;
      setState(() => _platformVersion = 'Unavailable');
    }
  }

  Future<void> _initialize() async {
    _log('INIT', 'Controller initialization started');
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _initialization = 'Initialized');
      _log('INIT', 'Controller initialized');
    } on CaptureException catch (error) {
      if (!mounted) return;
      setState(() {
        _initialization = 'Initialization failed';
        _error = error.reason.name;
      });
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    final state = _controller.state.value;
    final capability = _controller.capabilities.screenshots;
    final reason = state.reason;
    final now = DateTime.now();
    final previousStatus = _previousStatus;
    _previousStatus = state.status;
    _log('STATE', 'Continuous capture: ${state.status.name}, ${reason?.name}');
    _log('CAPABILITY', 'Screenshot detection: ${_describe(capability)}');

    setState(() {
      _lastStateUpdate = now;
      switch (reason) {
        case CaptureReason.transportFailure:
        case CaptureReason.protocolFailure:
        case CaptureReason.initializationTimeout:
        case CaptureReason.ambiguousHost:
          _recordError(reason!, now);
        case CaptureReason.backgrounded:
        case CaptureReason.detached:
        case CaptureReason.initializing:
        case CaptureReason.disposed:
          break;
        case CaptureReason.unsupportedPlatform:
          break;
        default:
          if (reason == null &&
              (previousStatus == CaptureStatus.active ||
                  previousStatus == CaptureStatus.inactive)) {
            break;
          }
          // Snapshots are applied to state and capabilities, rather than
          // published as CaptureEvents. Their session metadata is private.
          _addHistory('Snapshot received · ${_describe(capability)}', now);
          _log('SESSION', 'Observation snapshot applied');
          if (capability.reason case CaptureReason.registrationFailed) {
            _recordError(CaptureReason.registrationFailed, now);
          }
      }
    });
  }

  void _onEvent(CaptureEvent event) {
    if (!mounted) return;
    final details = switch (event) {
      ScreenshotTaken() => 'Screenshot detected',
      CaptureStateChanged(:final status) =>
        'Capture state changed · ${status.name}',
      CaptureStateInvalidated(:final reason) =>
        'Session invalidated · ${reason.name}',
      CaptureError(:final reason) => 'Capture error event · ${reason.name}',
    };
    final metadata = _eventMetadata(event);
    setState(() {
      _lastEvent = event;
      if (event is ScreenshotTaken) {
        _lastScreenshot = event;
        _screenshotCount++;
      }
      if (event is CaptureError) _error = event.reason.name;
      _addHistory('$details · $metadata', event.observedAt);
    });
    _log(
      event is ScreenshotTaken ? 'SCREENSHOT' : 'EVENT',
      '$details · $metadata',
    );
  }

  void _recordError(CaptureReason reason, DateTime time) {
    _error = reason.name;
    _addHistory('Capture observation error · ${reason.name}', time);
    _log('ERROR', 'Capture observation failed: ${reason.name}');
  }

  void _addHistory(String entry, DateTime time) {
    _history.insert(0, '$entry\n${_timestamp(time)}');
    if (_history.length > _historyLimit) _history.removeLast();
  }

  static String _describe(CaptureCapability capability) {
    final support = switch (capability.support) {
      CaptureSupport.supported => 'Supported',
      CaptureSupport.unavailable => 'Unsupported',
      CaptureSupport.temporarilyUnavailable => 'Temporarily unavailable',
    };
    return [
      support,
      if (capability.scope != CaptureScope.unknown) capability.scope.name,
      if (capability.reason case final reason?) reason.name,
    ].join(' · ');
  }

  static String _eventMetadata(CaptureEvent event) =>
      'Session ${event.session}, sequence ${event.sequence} · ${event.scope.name}';

  static String _timestamp(DateTime time) => time.toUtc().toIso8601String();

  static void _log(String stage, String message) {
    if (kDebugMode) debugPrint('[FSP][$stage] $message');
  }

  @override
  void dispose() {
    _controller.state.removeListener(_onStateChanged);
    unawaited(_events.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _controller.capabilities;
    final state = _controller.state.value;
    final lastScreenshot = _lastScreenshot;
    final lastEvent = _lastEvent;
    final lastStateUpdate = _lastStateUpdate;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Screen Protection Test')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Device'),
              Text('Platform: $_platformVersion'),
              Text('Plugin: $_initialization'),
              const Divider(),
              Text(
                'Screenshot detection: ${_describe(capabilities.screenshots)}',
              ),
              Text(
                'Screenshots detected: $_screenshotCount',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text('On Android, press Power + Volume Down.'),
              if (lastScreenshot != null) ...[
                Text(
                  'Last screenshot time: ${_timestamp(lastScreenshot.observedAt)}',
                ),
                Text(
                  'Last screenshot event: ${_eventMetadata(lastScreenshot)}',
                ),
              ],
              if (lastEvent != null)
                Text('Latest event metadata: ${_eventMetadata(lastEvent)}'),
              const Divider(),
              Text('Continuous capture: ${state.status.name}'),
              if (state.scope != CaptureScope.unknown)
                Text('Continuous capture scope: ${state.scope.name}'),
              if (state.reason case final reason?)
                Text('Continuous capture reason: ${reason.name}'),
              if (lastStateUpdate != null)
                Text('Last state update: ${_timestamp(lastStateUpdate)}'),
              if (_error case final error?) Text('Last error: $error'),
              const Divider(),
              const Text('Recent events (newest first)'),
              if (_history.isEmpty) const Text('No events yet'),
              for (final entry in _history)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(entry),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
