import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/main.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa/src/folder_access.dart';
import 'package:sasa/src/secret_store.dart';
import 'package:sasa/src/setup_controller.dart';
import 'package:sasa_core/sasa_core.dart';

import 'fakes.dart';

void main() {
  late MemoryDeviceSettings settings;
  late MemorySecretStore secrets;
  late MemoryFolderAccess access;

  setUp(() {
    settings = MemoryDeviceSettings();
    secrets = MemorySecretStore();
    access = MemoryFolderAccess(nextPick: syncA);
  });

  Future<(SetupController, AppServices)> make({
    SourcePlatform platform = SourcePlatform.android,
    CalDavTester? tester,
  }) async {
    final s = testServices(
      platform: platform,
      settings: settings,
      secrets: secrets,
      access: access,
      tester: tester,
    );
    final c = s.setup();
    await c.load();
    return (c, s);
  }

  void fill(SetupController c, {String password = 'pw'}) => c
    ..setUrl('https://dav.example.org/')
    ..setUsername('me')
    ..setPassword(password);

  test('needs a folder first', () async {
    final (c, _) = await make();
    expect(c.blocker, contains('folder'));
    expect(await c.finish(), isFalse);
    expect(await settings.setupDone(), isFalse);
  });

  test('picking a folder counts the devices already in it', () async {
    final folder = access.folder(syncA.ref);
    await folder.write('Sasa/devices/linux-1/log-2026-11.jsonl', '');
    await folder.write('Sasa/devices/android-2/log-2026-11.jsonl', '');
    await folder.write('Sasa/devices/.stfolder/x', '');
    final (c, _) = await make();
    await c.pickFolder();
    expect(c.folder, syncA);
    expect(c.existingDevices, 2);
  });

  test('cancelling the picker keeps the current folder', () async {
    final (c, _) = await make();
    await c.pickFolder();
    access.nextPick = null;
    await c.pickFolder();
    expect(c.folder, syncA);
  });

  test('Android with DAVx⁵: the CalDAV account is optional', () async {
    final (c, s) = await make();
    await c.pickFolder();
    expect(c.useDavx, isTrue);
    expect(c.calDavRequired, isFalse);
    expect(c.blocker, isNull);
    expect(await c.finish(), isTrue);

    expect(await settings.syncFolder(), syncA);
    expect(await settings.setupDone(), isTrue);
    expect(await settings.forceCalDav(), isFalse);
    expect(secrets.account, isNull);
    // The folder now has a config.json with the defaults.
    final config = access.folder(syncA.ref).files['Sasa/config.json']!;
    expect(
      AppConfig.fromJson(jsonDecode(config) as Map<String, Object?>).categories,
      hasLength(6),
    );
    expect(s.data.isOpen, isTrue);
    expect(s.sources.setup!.decision.kind, SourceKind.davxProvider);
  });

  test('a half-filled optional account must be completed', () async {
    final (c, _) = await make();
    await c.pickFolder();
    c.setUrl('https://dav.example.org/');
    expect(c.usernameError, isNotNull);
    expect(c.blocker, contains('CalDAV'));
    expect(await c.finish(), isFalse);
  });

  test(
    'CalDAV on Android: account required, saved to secure storage',
    () async {
      final (c, s) = await make();
      await c.pickFolder();
      c.setUseDavx(false);
      expect(c.calDavRequired, isTrue);
      expect(c.blocker, isNotNull);
      fill(c);
      expect(c.blocker, isNull);
      expect(await c.finish(), isTrue);
      expect(secrets.account, testAccount);
      expect(await settings.forceCalDav(), isTrue);
      expect(s.sources.setup!.decision.kind, SourceKind.calDav);
    },
  );

  test('Linux: CalDAV only, no source choice', () async {
    access.nextPick = const FolderLocation(
      kind: FolderKind.path,
      ref: '/home/me/Sync',
      name: 'Sync',
    );
    final (c, _) = await make(platform: SourcePlatform.linux);
    await c.pickFolder();
    expect(c.isAndroid, isFalse);
    expect(c.useDavx, isFalse);
    expect(c.calDavRequired, isTrue);
    expect(c.blocker, isNotNull);
    fill(c);
    expect(await c.finish(), isTrue);
    expect(secrets.account, testAccount);
  });

  test('validates the URL and flags plain http', () async {
    final (c, _) = await make(platform: SourcePlatform.linux);
    c.setUrl('dav.example.org');
    expect(c.urlError, isNotNull);
    c.setUrl('http://dav.example.org/');
    expect(c.urlError, isNull);
    expect(c.urlInsecure, isTrue);
    c.setUrl('https://dav.example.org/');
    expect(c.urlInsecure, isFalse);
  });

  test('reopening prefills; an empty password keeps the saved one', () async {
    secrets.account = testAccount;
    settings = MemoryDeviceSettings(
      syncFolder: syncA,
      setupDone: true,
      forceCalDav: true,
    );
    final (c, _) = await make();
    expect(c.folder, syncA);
    expect(c.useDavx, isFalse);
    expect(c.url, 'https://dav.example.org/');
    expect(c.username, 'me');
    expect(c.hasSavedPassword, isTrue);
    expect(c.passwordError, isNull);
    c.setUsername('me2');
    expect(await c.finish(), isTrue);
    expect(secrets.account!.username, 'me2');
    expect(secrets.account!.password, 'pw');
  });

  test('changing folder releases the old one', () async {
    settings = MemoryDeviceSettings(syncFolder: syncA, setupDone: true);
    access.nextPick = syncB;
    final (c, _) = await make();
    await c.pickFolder();
    expect(await c.finish(), isTrue);
    expect(access.forgotten, [syncA]);
    expect(await settings.syncFolder(), syncB);
  });

  test('a folder that cannot be opened is reported, nothing saved', () async {
    final (c, _) = await make();
    await c.pickFolder();
    access.accessible = false;
    expect(await c.finish(), isFalse);
    expect(c.error, contains('Choose it again'));
    expect(await settings.setupDone(), isFalse);
    expect(await settings.syncFolder(), isNull);
  });

  group('test connection', () {
    test('needs a complete account and a tester', () async {
      final (c, _) = await make(tester: (_) async => 'ok');
      expect(c.canTestConnection, isFalse);
      fill(c);
      expect(c.canTestConnection, isTrue);
      final (noTester, _) = await make();
      fill(noTester);
      expect(noTester.canTestConnection, isFalse);
    });

    test('reports success and failure, reset by edits', () async {
      CalDavAccount? tried;
      var fail = false;
      final (c, _) = await make(
        tester: (a) async {
          tried = a;
          if (fail) {
            throw const ConnectionFailed('Wrong user name or password.');
          }
          return 'Connected: 1 calendar, 1 task list.';
        },
      );
      fill(c);
      await c.testConnection();
      expect(tried, testAccount);
      expect(c.connectionOk, isTrue);
      expect(c.connectionMessage, contains('Connected'));
      fail = true;
      await c.testConnection();
      expect(c.connectionOk, isFalse);
      expect(c.connectionMessage, 'Wrong user name or password.');
      c.setPassword('other');
      expect(c.connectionMessage, isNull);
    });
  });
}
