import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_screen_protection/flutter_screen_protection.dart';

final class FakeCapturePlatform implements CapturePlatform {
  FakeCapturePlatform({this.hostPlatform = CaptureHostPlatform.android});

  @override
  final CaptureHostPlatform hostPlatform;
  final sessions = <FakeCaptureSession>[];
  Future<void>? cancellationGate;

  FakeCaptureSession get current => sessions.last;

  @override
  Stream<Object?> observeCapture() {
    final session = FakeCaptureSession(cancellationGate);
    sessions.add(session);
    return session.stream;
  }
}

final class FakeCaptureSession {
  FakeCaptureSession(Future<void>? cancellationGate) {
    _controller = StreamController<Object?>(
      sync: true,
      onCancel: () async {
        cancellationCount++;
        await cancellationGate;
      },
    );
  }

  late final StreamController<Object?> _controller;
  int cancellationCount = 0;
  Stream<Object?> get stream => _controller.stream;

  void send(Object? packet) => _controller.add(packet);
  void fail(Object error) => _controller.addError(error);
  Future<void> interrupt() => _controller.close();
}

final _fixtures =
    jsonDecode(File('test/fixtures/capture_v1.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, Object?> packet(String name) =>
    Map<String, Object?>.of(_fixtures[name] as Map<String, dynamic>);

Iterable<String> get packetNames => _fixtures.keys;
