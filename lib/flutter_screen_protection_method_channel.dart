import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_screen_protection_platform_interface.dart';

/// An implementation of [FlutterScreenProtectionPlatform] that uses method channels.
class MethodChannelFlutterScreenProtection extends FlutterScreenProtectionPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_screen_protection');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
