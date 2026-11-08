import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'davx_bridge_method_channel.dart';

abstract class DavxBridgePlatform extends PlatformInterface {
  /// Constructs a DavxBridgePlatform.
  DavxBridgePlatform() : super(token: _token);

  static final Object _token = Object();

  static DavxBridgePlatform _instance = MethodChannelDavxBridge();

  /// The default instance of [DavxBridgePlatform] to use.
  ///
  /// Defaults to [MethodChannelDavxBridge].
  static DavxBridgePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DavxBridgePlatform] when
  /// they register themselves.
  static set instance(DavxBridgePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
