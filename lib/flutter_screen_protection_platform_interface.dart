import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_screen_protection_method_channel.dart';

abstract class FlutterScreenProtectionPlatform extends PlatformInterface {
  /// Constructs a FlutterScreenProtectionPlatform.
  FlutterScreenProtectionPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterScreenProtectionPlatform _instance = MethodChannelFlutterScreenProtection();

  /// The default instance of [FlutterScreenProtectionPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterScreenProtection].
  static FlutterScreenProtectionPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterScreenProtectionPlatform] when
  /// they register themselves.
  static set instance(FlutterScreenProtectionPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
