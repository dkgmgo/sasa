import 'dart:io';

import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

/// The same contract runs against every [SyncFolder] implementation.
void contract(String name, Future<SyncFolder> Function() create) {
  group('$name contract', () {
    late SyncFolder f;
    setUp(() async => f = await create());

    test('missing directory lists as empty, missing file reads null', () async {
      expect(await f.list('nope'), isEmpty);
      expect(await f.list(''), isEmpty);
      expect(await f.read('nope/a.txt'), isNull);
    });

    test('append creates parents and appends in order', () async {
      await f.append('a/b/log.jsonl', 'one\n');
      await f.append('a/b/log.jsonl', 'two\n');
      expect(await f.read('a/b/log.jsonl'), 'one\ntwo\n');
    });

    test('write replaces the whole file and creates parents', () async {
      await f.write('x/config.json', '{"a":1}');
      await f.write('x/config.json', '{"b":2}');
      expect(await f.read('x/config.json'), '{"b":2}');
    });

    test('list reports files and directories, sorted by name', () async {
      await f.append('root/dev-b/log.jsonl', 'x\n');
      await f.append('root/dev-a/log.jsonl', 'x\n');
      await f.write('root/config.json', '{}');
      final entries = await f.list('root');
      expect(entries.map((e) => e.name), ['config.json', 'dev-a', 'dev-b']);
      expect(entries.map((e) => e.isDirectory), [false, true, true]);
    });

    test('write leaves no temporary file behind', () async {
      await f.write('root/config.json', '{}');
      expect((await f.list('root')).map((e) => e.name), ['config.json']);
    });

    test('delete removes a file and ignores a missing one', () async {
      await f.write('root/c.json', '{}');
      await f.delete('root/c.json');
      await f.delete('root/c.json');
      expect(await f.read('root/c.json'), isNull);
    });

    test('keeps UTF-8 text intact', () async {
      await f.append('u.txt', 'Réseaux · Sasa ⏱\n');
      expect(await f.read('u.txt'), 'Réseaux · Sasa ⏱\n');
    });

    test('rejects paths escaping the folder', () async {
      for (final bad in ['../x', 'a/../../x', '/etc/passwd', 'a//b', 'a/./b']) {
        expect(() => f.read(bad), throwsArgumentError, reason: bad);
        expect(() => f.append(bad, 'x'), throwsArgumentError, reason: bad);
      }
    });

    test('concurrent appends to one file keep every line whole', () async {
      await Future.wait([
        for (var i = 0; i < 50; i++) f.append('c/log.jsonl', 'line-$i\n'),
      ]);
      final lines = (await f.read('c/log.jsonl'))!.trim().split('\n');
      expect(lines.toSet(), {for (var i = 0; i < 50; i++) 'line-$i'});
    });
  });
}

void main() {
  contract('MemorySyncFolder', () async => MemorySyncFolder());

  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('sasa-sf-'));
  tearDown(() => tmp.delete(recursive: true));
  contract('IoSyncFolder', () async => IoSyncFolder(tmp.path));

  test('IoSyncFolder writes real files under its root', () async {
    final f = IoSyncFolder(tmp.path);
    await f.append('Sasa/devices/d/log.jsonl', 'x\n');
    expect(
      File('${tmp.path}/Sasa/devices/d/log.jsonl').readAsStringSync(),
      'x\n',
    );
  });

  test('IoSyncFolder ignores entries that are neither file nor dir', () async {
    final f = IoSyncFolder(tmp.path);
    await f.write('r/a.json', '{}');
    Link('${tmp.path}/r/dangling').createSync('${tmp.path}/missing');
    expect((await f.list('r')).map((e) => e.name), ['a.json']);
  });

  test(
    'MemorySyncFolder can simulate a crash halfway through a line',
    () async {
      final f = MemorySyncFolder();
      await f.append('log.jsonl', 'whole\n');
      f.corruptAppend('log.jsonl', '{"id":"tr');
      expect(await f.read('log.jsonl'), 'whole\n{"id":"tr');
    },
  );
}
