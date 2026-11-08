import 'dart:convert';

import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  late MemorySyncFolder folder;
  late FakeClock clock;
  late SasaFolder sasa;
  setUp(() {
    folder = MemorySyncFolder();
    clock = FakeClock(z(2026, 11, 8, 9));
    sasa = SasaFolder(folder);
  });

  String configText(DateTime updatedAt) =>
      jsonEncode(AppConfig.defaults(clock: FakeClock(updatedAt)).toJson());

  group('config.json', () {
    test('missing config loads as null', () async {
      expect(await sasa.loadConfig(), isNull);
    });

    test('save then load round-trips, as pretty JSON', () async {
      final c = AppConfig.defaults(clock: clock);
      await sasa.saveConfig(c);
      expect(await sasa.loadConfig(), c);
      expect(folder.files['Sasa/config.json'], contains('\n  "version": 1'));
    });

    test('loadOrCreateConfig writes defaults on first run only', () async {
      final first = await sasa.loadOrCreateConfig(clock);
      expect(first.categories, hasLength(6));
      expect(folder.files.keys, ['Sasa/config.json']);
      clock.advance(const Duration(days: 1));
      final again = await sasa.loadOrCreateConfig(clock);
      expect(again.updatedAt, first.updatedAt);
    });

    test('a corrupt config is a FormatException, never overwritten', () async {
      await folder.write('Sasa/config.json', '{"version": 1, "upd');
      await expectLater(sasa.loadConfig(), throwsFormatException);
      await expectLater(sasa.loadOrCreateConfig(clock), throwsFormatException);
      expect(folder.files['Sasa/config.json'], '{"version": 1, "upd');
    });
  });

  group('conflict copies', () {
    test(
      'detects Syncthing and Nextcloud conflict files for config.json',
      () async {
        await folder.write('Sasa/config.json', configText(z(2026, 11, 8)));
        final names = [
          'config.sync-conflict-20261108-101500-ABCDEFG.json',
          'config (conflicted copy 2026-11-08 101500).json',
          'config_conflict-20261108-101500.json',
        ];
        for (final n in names) {
          await folder.write('Sasa/$n', configText(z(2026, 11, 7)));
        }
        await folder.write('Sasa/config.json.bak', '{}');
        await folder.write('Sasa/other.sync-conflict-1-2-X.json', '{}');
        final found = await sasa.configConflicts();
        expect(found.map((c) => c.name), unorderedEquals(names));
        expect(found.every((c) => c.updatedAt == z(2026, 11, 7)), isTrue);
      },
    );

    test('an unreadable conflict copy is still reported', () async {
      await folder.write(
        'Sasa/config.sync-conflict-20261108-101500-ABCDEFG.json',
        'garbage',
      );
      final c = (await sasa.configConflicts()).single;
      expect(c.updatedAt, isNull);
    });

    test('no conflicts when there are none', () async {
      await sasa.saveConfig(AppConfig.defaults(clock: clock));
      expect(await sasa.configConflicts(), isEmpty);
    });

    test('keepNewestConfig: last writer wins and copies are removed', () async {
      await folder.write('Sasa/config.json', configText(z(2026, 11, 7)));
      const newer = 'config.sync-conflict-20261108-101500-AAAAAAA.json';
      const older = 'config.sync-conflict-20261108-101500-BBBBBBB.json';
      const broken = 'config.sync-conflict-20261108-101500-CCCCCCC.json';
      await folder.write('Sasa/$newer', configText(z(2026, 11, 8)));
      await folder.write('Sasa/$older', configText(z(2026, 11, 6)));
      await folder.write('Sasa/$broken', 'garbage');

      final kept = await sasa.keepNewestConfig();
      expect(kept.updatedAt, z(2026, 11, 8));
      expect((await sasa.loadConfig())!.updatedAt, z(2026, 11, 8));
      expect((await sasa.configConflicts()).map((c) => c.name), [
        broken,
      ], reason: 'unreadable copies are left for the user to inspect');
    });

    test('keepNewestConfig keeps the main file when it is newest', () async {
      await folder.write('Sasa/config.json', configText(z(2026, 11, 9)));
      const copy = 'config.sync-conflict-20261108-101500-AAAAAAA.json';
      await folder.write('Sasa/$copy', configText(z(2026, 11, 8)));
      final kept = await sasa.keepNewestConfig();
      expect(kept.updatedAt, z(2026, 11, 9));
      expect(await sasa.configConflicts(), isEmpty);
    });
  });

  test('eventLog shares the folder and root', () async {
    final log = sasa.eventLog(deviceId: 'linux-1', clock: clock);
    await log.append(const EnergyCheckin(energy: Energy.low));
    expect(folder.files.keys.single, 'Sasa/devices/linux-1/log-2026-11.jsonl');
  });
}
