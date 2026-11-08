
import 'flutter_screen_protection_platform_interface.dart';

class FlutterScreenProtection {
  Future<String?> getPlatformVersion() {
    return FlutterScreenProtectionPlatform.instance.getPlatformVersion();
  }
}
