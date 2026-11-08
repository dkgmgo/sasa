import 'package:shared_preferences/shared_preferences.dart';

/// Settings that belong to this device only, so they live outside the synced
/// folder.
abstract interface class DeviceSettings {
  /// Use CalDAV even when the DAVx⁵ provider is available (Android).
  Future<bool> forceCalDav();
  Future<void> setForceCalDav(bool value);
}

/// [DeviceSettings] in the platform's preferences store (SharedPreferences
/// on Android, a JSON file under the user's data dir on Linux). Readable from
/// background isolates too.
final class PrefsDeviceSettings implements DeviceSettings {
  PrefsDeviceSettings([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const forceCalDavKey = 'source.forceCalDav';

  final SharedPreferencesAsync _prefs;

  @override
  Future<bool> forceCalDav() async =>
      await _prefs.getBool(forceCalDavKey) ?? false;

  @override
  Future<void> setForceCalDav(bool value) =>
      _prefs.setBool(forceCalDavKey, value);
}

/// In-memory [DeviceSettings] for tests.
final class MemoryDeviceSettings implements DeviceSettings {
  MemoryDeviceSettings({bool forceCalDav = false}) : _force = forceCalDav;

  bool _force;

  @override
  Future<bool> forceCalDav() async => _force;

  @override
  Future<void> setForceCalDav(bool value) async => _force = value;
}
