import 'dart:io';

import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

void main() {
  group('CalDavAccount', () {
    final a = CalDavAccount(
      url: Uri.parse('https://dav.example.org/'),
      username: 'me',
      password: 's3cret',
    );

    test('round-trips through the secret map', () {
      expect(a.toSecrets(), {
        SecretKeys.calDavUrl: 'https://dav.example.org/',
        SecretKeys.calDavUsername: 'me',
        SecretKeys.calDavPassword: 's3cret',
      });
      expect(CalDavAccount.fromSecrets(a.toSecrets()), a);
    });

    test('is null when any part is missing or empty', () {
      final full = a.toSecrets();
      for (final k in full.keys) {
        expect(CalDavAccount.fromSecrets(Map.of(full)..remove(k)), isNull);
        expect(CalDavAccount.fromSecrets({...full, k: ''}), isNull);
      }
    });

    test('never shows the password', () {
      expect('$a', isNot(contains('s3cret')));
      expect('$a', contains('me'));
    });

    test('validates the URL', () {
      expect(CalDavAccount.checkUrl('https://dav.example.org'), isNull);
      expect(CalDavAccount.checkUrl('http://localhost:5232/'), isNull);
      expect(CalDavAccount.checkUrl(''), isNotNull);
      expect(CalDavAccount.checkUrl('dav.example.org'), isNotNull);
      expect(CalDavAccount.checkUrl('ftp://x.org'), isNotNull);
      expect(
        CalDavAccount.checkUrl('https://me:pw@dav.example.org'),
        contains('password'),
      );
    });

    test('plain http is flagged unless the host is local', () {
      expect(
        CalDavAccount.isInsecure(Uri.parse('http://dav.example.org')),
        isTrue,
      );
      expect(
        CalDavAccount.isInsecure(Uri.parse('http://localhost:5232')),
        isFalse,
      );
      expect(CalDavAccount.isInsecure(Uri.parse('http://127.0.0.1')), isFalse);
      expect(
        CalDavAccount.isInsecure(Uri.parse('https://dav.example.org')),
        isFalse,
      );
    });
  });

  group('parseEnvFile', () {
    test('reads KEY=value lines, quotes, comments and export', () {
      expect(
        parseEnvFile('''
# Sasa CalDAV account
SASA_CALDAV_URL=https://dav.example.org/
export SASA_CALDAV_USER="me"
SASA_CALDAV_PASSWORD='p#ss w=rd'

BROKEN LINE
EMPTY=
'''),
        {
          'SASA_CALDAV_URL': 'https://dav.example.org/',
          'SASA_CALDAV_USER': 'me',
          'SASA_CALDAV_PASSWORD': 'p#ss w=rd',
          'EMPTY': '',
        },
      );
    });

    test('maps env variables to a CalDAV account', () {
      final account = calDavAccountFromEnv({
        'SASA_CALDAV_URL': 'https://dav.example.org/',
        'SASA_CALDAV_USER': 'me',
        'SASA_CALDAV_PASSWORD': 'pw',
      });
      expect(account!.username, 'me');
      expect(calDavAccountFromEnv({'SASA_CALDAV_URL': 'https://x'}), isNull);
    });
  });

  group('DeviceFile', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('sasa-df-'));
    tearDown(() => tmp.delete(recursive: true));

    test('missing file reads as empty', () async {
      final f = DeviceFile('${tmp.path}/sasa/device.json');
      final d = await f.read();
      expect(d.deviceId, isNull);
      expect(d.syncFolder, isNull);
    });

    test('round-trips and creates the directory', () async {
      final f = DeviceFile('${tmp.path}/sasa/device.json');
      await f.write(
        const DeviceInfo(
          deviceId: 'linux-1a2b3c4d',
          syncFolder: '/home/me/Sync',
        ),
      );
      final d = await f.read();
      expect(d.deviceId, 'linux-1a2b3c4d');
      expect(d.syncFolder, '/home/me/Sync');
    });

    test('a corrupt file is a FormatException', () async {
      File('${tmp.path}/device.json').writeAsStringSync('{nope');
      await expectLater(
        DeviceFile('${tmp.path}/device.json').read(),
        throwsFormatException,
      );
    });

    test('default path follows XDG_CONFIG_HOME, then HOME', () {
      expect(
        DeviceFile.defaultPath({'XDG_CONFIG_HOME': '/x', 'HOME': '/h'}),
        '/x/sasa/device.json',
      );
      expect(
        DeviceFile.defaultPath({'HOME': '/h'}),
        '/h/.config/sasa/device.json',
      );
      expect(DeviceFile.defaultPath({}), isNull);
    });
  });
}
