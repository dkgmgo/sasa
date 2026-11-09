import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:saf_folder/saf_folder.dart';
import 'package:sasa/src/data_controller.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa/src/folder_access.dart';
import 'package:sasa_core/sasa_core.dart';

import 'fakes.dart';

/// A folder whose grant was revoked after opening.
final class RevokedAccess extends MemoryFolderAccess {
  bool revoked = false;

  @override
  SyncFolder open(FolderLocation location) =>
      _Revocable(super.open(location), () => revoked);
}

final class _Revocable implements SyncFolder {
  _Revocable(this.inner, this.revoked);
  final SyncFolder inner;
  final bool Function() revoked;

  Future<T> _guard<T>(Future<T> Function() f) {
    if (revoked()) throw const SafAccessLost('revoked');
    return f();
  }

  @override
  Future<List<FolderEntry>> list(String dir) => _guard(() => inner.list(dir));
  @override
  Future<String?> read(String path) => _guard(() => inner.read(path));
  @override
  Future<void> append(String path, String text) =>
      _guard(() => inner.append(path, text));
  @override
  Future<void> write(String path, String text) =>
      _guard(() => inner.write(path, text));
  @override
  Future<void> delete(String path) => _guard(() => inner.delete(path));
}

void main() {
  final clock = FakeClock(DateTime.utc(2026, 11, 8, 9));

  DataController make(MemoryFolderAccess access, {FolderLocation? saved}) =>
      DataController(
        settings: MemoryDeviceSettings(
          deviceId: 'android-1',
          syncFolder: saved,
        ),
        access: access,
        clock: clock,
      );

  test('nothing saved: openSaved is false', () async {
    expect(await make(MemoryFolderAccess()).openSaved(), isFalse);
  });

  test('opens, creates config and merges other devices\' logs', () async {
    final access = MemoryFolderAccess();
    final other = EventLog(
      folder: access.folder(syncA.ref),
      deviceId: 'linux-1',
      clock: clock,
    );
    await other.append(const EnergyCheckin(energy: Energy.low));

    final d = make(access, saved: syncA);
    expect(await d.openSaved(), isTrue);
    expect(d.isOpen, isTrue);
    expect(d.config!.categories, hasLength(6));
    expect(d.snapshot!.events, hasLength(1));

    clock.advance(const Duration(minutes: 1));
    await d.log!.append(const EnergyCheckin(energy: Energy.high));
    await d.reload();
    expect(d.snapshot!.devices, ['android-1', 'linux-1']);
    expect(d.snapshot!.state.latestEnergy!.energy, Energy.high);
  });

  test('shows config conflicts and resolves them, newest wins', () async {
    final access = MemoryFolderAccess();
    final folder = access.folder(syncA.ref);
    String config(DateTime t) =>
        jsonEncode(AppConfig.defaults(clock: FakeClock(t)).toJson());
    await folder.write('Sasa/config.json', config(DateTime.utc(2026, 11, 7)));
    await folder.write(
      'Sasa/config.sync-conflict-20261108-090000-ABCDEFG.json',
      config(DateTime.utc(2026, 11, 8)),
    );
    final d = make(access, saved: syncA);
    await d.openSaved();
    expect(d.conflicts, hasLength(1));
    await d.keepNewestConfig();
    expect(d.conflicts, isEmpty);
    expect(d.config!.updatedAt, DateTime.utc(2026, 11, 8));
  });

  test('a corrupt config is reported and left alone', () async {
    final access = MemoryFolderAccess();
    await access.folder(syncA.ref).write('Sasa/config.json', '{"version"');
    final d = make(access, saved: syncA);
    expect(await d.openSaved(), isTrue);
    expect(d.config, isNull);
    expect(d.error, contains('config.json'));
    expect(access.folder(syncA.ref).files['Sasa/config.json'], '{"version"');
  });

  test('an inaccessible folder is reported as lost', () async {
    final access = MemoryFolderAccess()..accessible = false;
    final d = make(access, saved: syncA);
    expect(await d.openSaved(), isFalse);
    expect(d.accessLost, isTrue);
    expect(d.isOpen, isFalse);
  });

  test('access revoked while open is reported as lost', () async {
    final access = RevokedAccess();
    final d = make(access, saved: syncA);
    expect(await d.openSaved(), isTrue);
    access.revoked = true;
    await d.reload();
    expect(d.accessLost, isTrue);
    expect(d.log, isNull);
  });

  group('updateConfig', () {
    const rule = MappingRule(
      field: MatchField.calendar,
      pattern: 'Cours',
      categoryId: 'teaching',
    );

    Future<AppConfig> onDisk(MemoryFolderAccess access) async =>
        (await SasaFolder(access.folder(syncA.ref)).loadConfig())!;

    test('saves the edit with a new updatedAt', () async {
      final access = MemoryFolderAccess();
      final d = make(access, saved: syncA);
      await d.openSaved();
      final before = d.config!.updatedAt;
      clock.advance(const Duration(minutes: 5));

      expect(await d.updateConfig(ConfigEdits.addRule(rule)), isNull);
      expect(d.config!.rules, [rule]);
      expect(d.config!.updatedAt.isAfter(before), isTrue);
      expect(await onDisk(access), d.config);
    });

    test(
      'applies the edit to the newest file, keeping other changes',
      () async {
        final access = MemoryFolderAccess();
        final d = make(access, saved: syncA);
        await d.openSaved();
        // Another device renamed a category after this one loaded.
        final folder = SasaFolder(access.folder(syncA.ref));
        final synced = await folder.loadConfig();
        await folder.saveConfig(
          ConfigEdits.putCategory(
            synced!.categoryById('admin')!.copyWith(name: 'Paperwork'),
          )(synced),
        );

        expect(await d.updateConfig(ConfigEdits.addRule(rule)), isNull);
        final saved = await onDisk(access);
        expect(saved.rules, [rule]);
        expect(saved.categoryById('admin')!.name, 'Paperwork');
      },
    );

    test('a vanished target gives a message and reloads', () async {
      final access = MemoryFolderAccess();
      final d = make(access, saved: syncA);
      await d.openSaved();
      final message = await d.updateConfig(ConfigEdits.removeRule(rule));
      expect(message, contains('another device'));
      expect(d.config!.rules, isEmpty);
    });

    test('no open folder gives a message', () async {
      final d = make(MemoryFolderAccess());
      expect(await d.updateConfig(ConfigEdits.addRule(rule)), isNotNull);
    });
  });
}
