import 'davx_bridge_platform_interface.dart';

class DavxBridge {
  Future<String?> getPlatformVersion() {
    return DavxBridgePlatform.instance.getPlatformVersion();
  }
}
