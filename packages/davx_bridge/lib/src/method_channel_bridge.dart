import 'package:flutter/services.dart';
import 'package:sasa_core/sasa_core.dart';

import 'provider_rows.dart';

/// [DavxBridgeApi] over the plugin's method channel.
///
/// Usable from the UI isolate and from a WorkManager background isolate (the
/// plugin is registered in every engine). Missing permissions, a missing
/// provider and non-Android platforms surface as [SourceUnavailable].
final class DavxBridge implements DavxBridgeApi {
  DavxBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'fr.dkgmgo.davx_bridge';

  /// Error codes from the Kotlin side that mean "use another source".
  static const unavailableCodes = {'permission_denied', 'provider_unavailable'};

  final MethodChannel _channel;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      if (unavailableCodes.contains(e.code)) {
        throw SourceUnavailable('${e.code}: ${e.message ?? method}');
      }
      rethrow;
    } on MissingPluginException {
      throw const SourceUnavailable('DAVx⁵ bridge not available here');
    }
  }

  Future<Map<Object?, Object?>> _map(
    String method, [
    Map<String, Object?>? args,
  ]) async => await _call<Map<Object?, Object?>>(method, args) ?? const {};

  @override
  Future<BridgeStatus> status() async =>
      BridgeStatus.fromMap(await _map('status'));

  @override
  Future<BridgeStatus> requestPermissions({
    bool calendar = true,
    bool tasks = true,
  }) async => BridgeStatus.fromMap(
    await _map('requestPermissions', {'calendar': calendar, 'tasks': tasks}),
  );

  @override
  Future<List<ProviderCalendar>> calendars() async => [
    for (final r in rowsOf(await _call<List<Object?>>('calendars')))
      ProviderCalendar.fromMap(r),
  ];

  @override
  Future<List<ProviderInstance>> instances(DateTime start, DateTime end) async {
    final rows = await _call<List<Object?>>('instances', {
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
    final out = <ProviderInstance>[];
    for (final r in rowsOf(rows)) {
      try {
        out.add(ProviderInstance.fromMap(r));
      } on FormatException {
        continue; // A row without a start time cannot be placed.
      }
    }
    return out;
  }

  @override
  Future<ProviderTasks> tasks() async =>
      ProviderTasks.fromMap(await _map('tasks'));
}
