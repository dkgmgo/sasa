import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa/src/folder_access.dart';
import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('forceCalDav defaults to false and persists', () async {
    final s = PrefsDeviceSettings();
    expect(await s.forceCalDav(), isFalse);
    await s.setForceCalDav(true);
    expect(await PrefsDeviceSettings().forceCalDav(), isTrue);
  });

  test('theme mode defaults to system and persists', () async {
    final s = PrefsDeviceSettings();
    expect(await s.themeMode(), ThemeMode.system);
    await s.setThemeMode(ThemeMode.light);
    expect(await PrefsDeviceSettings().themeMode(), ThemeMode.light);
    await s.setThemeMode(ThemeMode.dark);
    expect(await PrefsDeviceSettings().themeMode(), ThemeMode.dark);
  });

  test('an unknown stored theme mode falls back to system', () async {
    await SharedPreferencesAsync().setString(
      PrefsDeviceSettings.themeModeKey,
      'sepia',
    );
    expect(await PrefsDeviceSettings().themeMode(), ThemeMode.system);
  });

  test('device id is generated once, folder-safe, and kept', () async {
    final s = PrefsDeviceSettings(idPrefix: 'android', random: Random(1));
    final id = await s.deviceId();
    expect(id, matches(RegExp(r'^android-[0-9a-f]{8}$')));
    expect(isValidDeviceId(id), isTrue);
    expect(await PrefsDeviceSettings(random: Random(2)).deviceId(), id);
  });

  test('synced folder and setup flag persist', () async {
    final s = PrefsDeviceSettings();
    expect(await s.syncFolder(), isNull);
    expect(await s.setupDone(), isFalse);
    await s.setSyncFolder(syncA);
    await s.setSetupDone(true);
    final again = PrefsDeviceSettings();
    expect(await again.syncFolder(), syncA);
    expect(await again.setupDone(), isTrue);
    await again.setSyncFolder(null);
    expect(await again.syncFolder(), isNull);
  });

  group('with a device file (Linux)', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('sasa-ds-'));
    tearDown(() => tmp.delete(recursive: true));

    test('id and folder are shared with the CLI through device.json', () async {
      final file = DeviceFile('${tmp.path}/sasa/device.json');
      final s = PrefsDeviceSettings(
        deviceFile: file,
        idPrefix: 'linux',
        random: Random(3),
      );
      final id = await s.deviceId();
      await s.setSyncFolder(PathFolderAccess.locationOf('/home/me/Sync'));

      final info = await file.read();
      expect(info.deviceId, id);
      expect(info.syncFolder, '/home/me/Sync');
      expect(id, startsWith('linux-'));
      final folder = await s.syncFolder();
      expect(folder!.kind, FolderKind.path);
      expect(folder.name, 'Sync');
      expect(await s.deviceId(), id);
    });
  });

  test('MemoryDeviceSettings', () async {
    final s = MemoryDeviceSettings(forceCalDav: true);
    expect(await s.forceCalDav(), isTrue);
    await s.setForceCalDav(false);
    expect(await s.forceCalDav(), isFalse);
    expect(await s.deviceId(), 'test-device');
  });
}
