import 'flutter_screen_protection_platform_interface.dart';

export 'src/capture_controller.dart';
export 'src/capture_models.dart';
export 'src/capture_platform.dart' show CapturePlatform, ChannelCapturePlatform;

class FlutterScreenProtection {
  Future<String?> getPlatformVersion() {
    return FlutterScreenProtectionPlatform.instance.getPlatformVersion();
  }
}
