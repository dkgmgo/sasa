import 'dart:convert';
import 'dart:io';

import 'package:sasa_cli/sasa_cli.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('sasa-cli-'));
  tearDown(() => tmp.delete(recursive: true));

  const envAccount = {
    'SASA_CALDAV_URL': 'https://env.example.org/',
    'SASA_CALDAV_USER': 'env-user',
    'SASA_CALDAV_PASSWORD': 'env-pw',
  };

  Keyring keyring(Map<String, String>? secrets) =>
      () async => secrets;

  String envFile(String body, {int mode = 0x180 /* 0600 */}) {
    final f = File('${tmp.path}/secrets.env')..writeAsStringSync(body);
    Process.runSync('chmod', [mode.toRadixString(8), f.path]);
    return f.path;
  }

  test('process environment wins', () async {
    final r = await findCalDavAccount(
      env: envAccount,
      envFilePath: envFile('SASA_CALDAV_URL=https://file/\n'),
      keyring: keyring({SecretKeys.calDavUrl: 'https://kr/'}),
    );
    expect(r.account!.username, 'env-user');
    expect(r.source, 'environment');
  });

  test('then the env file', () async {
    final path = envFile(
      envAccount.entries.map((e) => '${e.key}=${e.value}').join('\n'),
    );
    final r = await findCalDavAccount(
      env: const {},
      envFilePath: path,
      keyring: keyring(null),
    );
    expect(r.account!.url, Uri.parse('https://env.example.org/'));
    expect(r.source, path);
    expect(r.warnings, isEmpty);
  });

  test('warns when the env file is readable by others', () async {
    final path = envFile(
      envAccount.entries.map((e) => '${e.key}=${e.value}').join('\n'),
      mode: 0x1a4, // 0644
    );
    final r = await findCalDavAccount(
      env: const {},
      envFilePath: path,
      keyring: keyring(null),
    );
    expect(r.account, isNotNull);
    expect(r.warnings.single, contains('chmod 600'));
  });

  test('refuses an env file inside the synced folder', () async {
    Directory('${tmp.path}/Sync').createSync();
    final f = File('${tmp.path}/Sync/secrets.env')
      ..writeAsStringSync(
        envAccount.entries.map((e) => '${e.key}=${e.value}').join('\n'),
      );
    final r = await findCalDavAccount(
      env: const {},
      envFilePath: f.path,
      syncFolder: '${tmp.path}/Sync',
      keyring: keyring(null),
    );
    expect(r.account, isNull);
    expect(r.warnings.single, contains('synced folder'));
  });

  test('then the app keyring entry', () async {
    final r = await findCalDavAccount(
      env: const {},
      envFilePath: '${tmp.path}/missing.env',
      keyring: keyring(const {
        SecretKeys.calDavUrl: 'https://kr.example.org/',
        SecretKeys.calDavUsername: 'kr-user',
        SecretKeys.calDavPassword: 'kr-pw',
      }),
    );
    expect(r.account!.username, 'kr-user');
    expect(r.source, 'keyring');
  });

  test('nothing configured', () async {
    final r = await findCalDavAccount(
      env: const {},
      envFilePath: null,
      keyring: keyring(null),
    );
    expect(r.account, isNull);
    expect(r.source, isNull);
  });

  group('secret-tool keyring', () {
    test('looks up the app entry and parses its JSON', () async {
      late List<String> args;
      final kr = secretToolKeyring(
        run: (exe, a) async {
          expect(exe, 'secret-tool');
          args = a;
          return ProcessResult(0, 0, jsonEncode({'caldav.username': 'me'}), '');
        },
      );
      expect(await kr(), {'caldav.username': 'me'});
      expect(args, ['lookup', 'account', 'fr.dkgmgo.sasa.secureStorage']);
    });

    test('missing entry, missing tool or garbage give null', () async {
      expect(
        await secretToolKeyring(
          run: (_, _) async => ProcessResult(0, 1, '', ''),
        )(),
        isNull,
      );
      expect(
        await secretToolKeyring(
          run: (_, _) async => throw const ProcessException('secret-tool', []),
        )(),
        isNull,
      );
      expect(
        await secretToolKeyring(
          run: (_, _) async => ProcessResult(0, 0, 'not json', ''),
        )(),
        isNull,
      );
    });
  });
}
