import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'davx_bridge_platform_interface.dart';

/// An implementation of [DavxBridgePlatform] that uses method channels.
class MethodChannelDavxBridge extends DavxBridgePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('davx_bridge');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
