import 'dart:convert';
import 'dart:io';

import 'package:sasa_cli/sasa_cli.dart';
import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String sync;
  late Map<String, String> env;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sasa-cli-');
    sync = '${tmp.path}/Sync';
    Directory(sync).createSync();
    env = {'XDG_CONFIG_HOME': '${tmp.path}/config'};
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<(int, String, String)> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runSasa(
      args,
      out,
      err,
      env: env,
      keyring: () async => null,
    );
    return (code, '$out', '$err');
  }

  test('without a folder it explains how to set one', () async {
    final (code, _, err) = await run(['status']);
    expect(code, exitConfig);
    expect(err, contains('--folder'));
  });

  test(
    'reports device, events, conflicts and CalDAV without secrets',
    () async {
      await DeviceFile('${tmp.path}/config/sasa/device.json')
          .write(DeviceInfo(deviceId: 'linux-1a2b3c4d', syncFolder: sync));
      final folder = SasaFolder(IoSyncFolder(sync));
      final clock = FakeClock(DateTime.utc(2026, 11, 8, 9));
      await folder.loadOrCreateConfig(clock);
      await File('$sync/Sasa/config.sync-conflict-20261108-1-ABC.json')
          .writeAsString(jsonEncode(AppConfig.defaults(clock: clock).toJson()));
      final phone = folder.eventLog(deviceId: 'android-9', clock: clock);
      await phone.append(const EnergyCheckin(energy: Energy.low));
      await phone.append(const EnergyCheckin(energy: Energy.high));
      File('$sync/Sasa/devices/android-9/log-2026-11.jsonl')
          .writeAsStringSync('{"torn', mode: FileMode.append);

      env.addAll({
        'SASA_CALDAV_URL': 'https://dav.example.org/',
        'SASA_CALDAV_USER': 'me',
        'SASA_CALDAV_PASSWORD': 'hunter2',
      });
      final (code, out, err) = await run(['status']);
      expect(err, isEmpty);
      expect(code, 0);
      expect(out, contains('Device: linux-1a2b3c4d'));
      expect(out, contains('Folder: $sync'));
      expect(out, contains('Events: 2 from 1 device (android-9)'));
      expect(out, contains('1 unreadable line'));
      expect(out, contains('config.sync-conflict-20261108-1-ABC.json'));
      expect(
        out,
        contains('CalDAV: me @ https://dav.example.org/ (environment)'),
      );
      expect(out, isNot(contains('hunter2')));
    },
  );

  test('--folder overrides device.json and never writes to it', () async {
    final (code, out, _) = await run(['status', '--folder', sync]);
    expect(code, 0);
    expect(out, contains('Folder: $sync'));
    expect(out, contains('Device: not set'));
    expect(out, contains('Config: none yet'));
    expect(out, contains('CalDAV: not configured'));
    expect(Directory('$sync/Sasa').existsSync(), isFalse, reason: 'read-only');
  });

  test('a folder that does not exist is an error', () async {
    final (code, _, err) = await run(['status', '--folder', '${tmp.path}/x']);
    expect(code, exitConfig);
    expect(err, contains('does not exist'));
  });
}
