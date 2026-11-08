import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';
import 'package:flutter_screen_protection/flutter_screen_protection_platform_interface.dart';
import 'package:flutter_screen_protection/flutter_screen_protection_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterScreenProtectionPlatform
    with MockPlatformInterfaceMixin
    implements FlutterScreenProtectionPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterScreenProtectionPlatform initialPlatform = FlutterScreenProtectionPlatform.instance;

  test('$MethodChannelFlutterScreenProtection is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterScreenProtection>());
  });

  test('getPlatformVersion', () async {
    FlutterScreenProtection flutterScreenProtectionPlugin = FlutterScreenProtection();
    MockFlutterScreenProtectionPlatform fakePlatform = MockFlutterScreenProtectionPlatform();
    FlutterScreenProtectionPlatform.instance = fakePlatform;

    expect(await flutterScreenProtectionPlugin.getPlatformVersion(), '42');
  });
}
