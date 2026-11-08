import 'package:davx_bridge/davx_bridge.dart';
import 'package:davx_bridge/davx_bridge_method_channel.dart';
import 'package:davx_bridge/davx_bridge_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDavxBridgePlatform
    with MockPlatformInterfaceMixin
    implements DavxBridgePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DavxBridgePlatform initialPlatform = DavxBridgePlatform.instance;

  test('$MethodChannelDavxBridge is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDavxBridge>());
  });

  test('getPlatformVersion', () async {
    final DavxBridge davxBridgePlugin = DavxBridge();
    final MockDavxBridgePlatform fakePlatform = MockDavxBridgePlatform();
    DavxBridgePlatform.instance = fakePlatform;

    expect(await davxBridgePlugin.getPlatformVersion(), '42');
  });
}
