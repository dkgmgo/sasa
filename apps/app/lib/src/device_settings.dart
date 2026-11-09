import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'folder_access.dart';

/// Settings that belong to this device only, so they live outside the synced
/// folder. Secrets are not here: see `SecretStore`.
abstract interface class DeviceSettings {
  /// Use CalDAV even when the DAVx⁵ provider is available (Android).
  Future<bool> forceCalDav();
  Future<void> setForceCalDav(bool value);

  /// This device's id (its folder under `Sasa/devices/`), created on first
  /// use and then never changed.
  Future<String> deviceId();

  /// The synced folder, or null before setup.
  Future<FolderLocation?> syncFolder();
  Future<void> setSyncFolder(FolderLocation? value);

  /// True once the first-run setup was completed.
  Future<bool> setupDone();
  Future<void> setSetupDone(bool value);

  /// Light, dark, or following the system ([ThemeMode.system], the default).
  Future<ThemeMode> themeMode();
  Future<void> setThemeMode(ThemeMode value);
}

/// [DeviceSettings] in the platform's preferences store (SharedPreferences
/// on Android, a JSON file under the user's data dir on Linux). Readable from
/// background isolates too.
///
/// With a [deviceFile] (Linux), the device id and the folder path live in
/// `~/.config/sasa/device.json` instead, so the `sasa` CLI writes as the same
/// device to the same folder.
final class PrefsDeviceSettings implements DeviceSettings {
  PrefsDeviceSettings({
    SharedPreferencesAsync? prefs,
    this.deviceFile,
    this.idPrefix = 'device',
    Random? random,
  }) : _prefs = prefs ?? SharedPreferencesAsync(),
       _random = random ?? Random.secure();

  static const forceCalDavKey = 'source.forceCalDav';
  static const deviceIdKey = 'device.id';
  static const syncFolderKey = 'folder.location';
  static const setupDoneKey = 'setup.done';
  static const themeModeKey = 'ui.themeMode';

  final SharedPreferencesAsync _prefs;
  final DeviceFile? deviceFile;

  /// Start of generated ids, e.g. `android` or `linux`.
  final String idPrefix;
  final Random _random;

  @override
  Future<bool> forceCalDav() async =>
      await _prefs.getBool(forceCalDavKey) ?? false;

  @override
  Future<void> setForceCalDav(bool value) =>
      _prefs.setBool(forceCalDavKey, value);

  @override
  Future<String> deviceId() async {
    final file = deviceFile;
    if (file != null) {
      final info = await file.read();
      final id = info.deviceId;
      if (id != null && isValidDeviceId(id)) return id;
      final fresh = generateDeviceId(idPrefix, _random);
      await file.write(info.copyWith(deviceId: fresh));
      return fresh;
    }
    final id = await _prefs.getString(deviceIdKey);
    if (id != null && isValidDeviceId(id)) return id;
    final fresh = generateDeviceId(idPrefix, _random);
    await _prefs.setString(deviceIdKey, fresh);
    return fresh;
  }

  @override
  Future<FolderLocation?> syncFolder() async {
    final file = deviceFile;
    if (file != null) {
      final path = (await file.read()).syncFolder;
      if (path == null) return null;
      return PathFolderAccess.locationOf(path);
    }
    final raw = await _prefs.getString(syncFolderKey);
    if (raw == null) return null;
    try {
      return FolderLocation.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return null; // Unreadable: setup asks again.
    }
  }

  @override
  Future<void> setSyncFolder(FolderLocation? value) async {
    final file = deviceFile;
    if (file != null) {
      final info = await file.read();
      await file.write(
        DeviceInfo(deviceId: info.deviceId, syncFolder: value?.ref),
      );
      return;
    }
    if (value == null) return _prefs.remove(syncFolderKey);
    return _prefs.setString(syncFolderKey, jsonEncode(value.toJson()));
  }

  @override
  Future<bool> setupDone() async => await _prefs.getBool(setupDoneKey) ?? false;

  @override
  Future<void> setSetupDone(bool value) => _prefs.setBool(setupDoneKey, value);

  @override
  Future<ThemeMode> themeMode() async {
    final name = await _prefs.getString(themeModeKey);
    return ThemeMode.values.where((m) => m.name == name).firstOrNull ??
        ThemeMode.system;
  }

  @override
  Future<void> setThemeMode(ThemeMode value) =>
      _prefs.setString(themeModeKey, value.name);
}

/// In-memory [DeviceSettings] for tests.
final class MemoryDeviceSettings implements DeviceSettings {
  MemoryDeviceSettings({
    bool forceCalDav = false,
    String deviceId = 'test-device',
    FolderLocation? syncFolder,
    bool setupDone = false,
    ThemeMode themeMode = ThemeMode.system,
  }) : _theme = themeMode,
       _force = forceCalDav,
       _id = deviceId,
       _folder = syncFolder,
       _done = setupDone;

  ThemeMode _theme;
  bool _force;
  final String _id;
  FolderLocation? _folder;
  bool _done;

  @override
  Future<bool> forceCalDav() async => _force;

  @override
  Future<void> setForceCalDav(bool value) async => _force = value;

  @override
  Future<String> deviceId() async => _id;

  @override
  Future<FolderLocation?> syncFolder() async => _folder;

  @override
  Future<void> setSyncFolder(FolderLocation? value) async => _folder = value;

  @override
  Future<bool> setupDone() async => _done;

  @override
  Future<void> setSetupDone(bool value) async => _done = value;

  @override
  Future<ThemeMode> themeMode() async => _theme;

  @override
  Future<void> setThemeMode(ThemeMode value) async => _theme = value;
}
