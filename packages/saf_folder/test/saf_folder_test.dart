import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf_folder/saf_folder.dart';
import 'package:sasa_core/sasa_core.dart';

const tree =
    'content://com.android.externalstorage.documents/tree/primary%3ASync';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(SafFolder.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  /// The platform side, played by an in-memory folder.
  late MemorySyncFolder backing;
  Future<Object?> Function(MethodCall)? override;

  Future<Object?> platform(MethodCall call) async {
    calls.add(call);
    if (override != null) return override!(call);
    final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
    expect(args['treeUri'], call.method == 'pickTree' ? isNull : tree);
    final path = args['path'] as String? ?? '';
    final text = args['text'] as String?;
    switch (call.method) {
      case 'pickTree':
        return {'uri': tree, 'name': 'Sync'};
      case 'hasAccess':
        return true;
      case 'describe':
        return {'uri': tree, 'name': 'Sync'};
      case 'release':
        return null;
      case 'list':
        return [
          for (final e in await backing.list(path))
            {'name': e.name, 'isDirectory': e.isDirectory},
        ];
      case 'read':
        return backing.read(path);
      case 'append':
        await backing.append(path, text!);
        return null;
      case 'write':
        await backing.write(path, text!);
        return null;
      case 'delete':
        await backing.delete(path);
        return null;
    }
    throw MissingPluginException();
  }

  setUp(() {
    calls = [];
    backing = MemorySyncFolder();
    override = null;
    messenger.setMockMethodCallHandler(channel, platform);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  final api = SafFolder();

  test('pickTree returns the tree, null on cancel', () async {
    expect((await api.pickTree())!.name, 'Sync');
    expect(calls.single.arguments, <Object?, Object?>{});
    await api.pickTree(initialUri: tree);
    expect((calls.last.arguments as Map)['initialUri'], tree);

    override = (_) async => null;
    expect(await api.pickTree(), isNull);
  });

  test('SafSyncFolder drives an event log through the channel', () async {
    final folder = SafSyncFolder(api, tree);
    final clock = FakeClock(DateTime.utc(2026, 11, 8, 9));
    final log = EventLog(folder: folder, deviceId: 'android-1', clock: clock);
    await log.append(const EnergyCheckin(energy: Energy.high));
    await log.append(
      const SuggestionSkipped(activityId: 'a', categoryId: 'reading'),
    );
    expect(backing.files.keys, ['Sasa/devices/android-1/log-2026-11.jsonl']);

    final snap = await log.load();
    expect(snap.events, hasLength(2));
    expect(snap.state.latestEnergy!.energy, Energy.high);

    final sasa = SasaFolder(folder);
    await sasa.loadOrCreateConfig(clock);
    expect((await sasa.loadConfig())!.categories, hasLength(6));
    await folder.delete('Sasa/config.json');
    expect(await sasa.loadConfig(), isNull);
  });

  test('bad paths never reach the platform', () async {
    final folder = SafSyncFolder(api, tree);
    await expectLater(folder.read('../etc'), throwsArgumentError);
    await expectLater(folder.append('a//b', 'x'), throwsArgumentError);
    await expectLater(folder.list('/abs'), throwsArgumentError);
    expect(calls, isEmpty);
  });

  test('platform errors map to Dart exceptions', () async {
    Future<void> failWith(String code, Matcher m) async {
      override = (_) async =>
          throw PlatformException(code: code, message: code);
      await expectLater(api.read(tree, 'a'), throwsA(m));
    }

    await failWith('access_lost', isA<SafAccessLost>());
    await failWith('invalid_path', isArgumentError);
    await failWith(
      'io_error',
      isA<SafFolderException>().having((e) => e.code, 'code', 'io_error'),
    );
  });

  test('without the plugin (Linux, tests) calls fail clearly', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      api.hasAccess(tree),
      throwsA(
        isA<SafFolderException>().having((e) => e.code, 'code', 'unavailable'),
      ),
    );
  });
}
