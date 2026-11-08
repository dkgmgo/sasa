import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../support/append_worker.dart';

EventLog logFor(
  SyncFolder folder,
  String device,
  Clock clock, {
  int seed = 1,
}) => EventLog(
  folder: folder,
  deviceId: device,
  clock: clock,
  random: Random(seed),
);

const skipA = SuggestionSkipped(activityId: 'a', categoryId: 'reading');

/// Copies every file that [from] owns (its own device folder, as a sync
/// tool would) into [to]. Returns the paths copied.
Future<List<String>> syncDevice(
  MemorySyncFolder from,
  MemorySyncFolder to,
  String device,
) async {
  final prefix = 'Sasa/devices/$device/';
  final copied = <String>[];
  for (final MapEntry(:key, :value) in from.files.entries) {
    if (key.startsWith(prefix)) {
      await to.write(key, value);
      copied.add(key);
    }
  }
  return copied;
}

void main() {
  late MemorySyncFolder folder;
  late FakeClock clock;
  setUp(() {
    folder = MemorySyncFolder();
    clock = FakeClock(z(2026, 11, 8, 9));
  });

  test('rejects an unsafe device id', () {
    expect(
      () => EventLog(folder: folder, deviceId: '../x', clock: clock),
      throwsArgumentError,
    );
  });

  group('append', () {
    test('writes one JSON line to its own monthly file', () async {
      final log = logFor(folder, 'linux-1', clock);
      final e = await log.append(skipA);
      expect(e.ts, z(2026, 11, 8, 9));
      expect(e.device, 'linux-1');
      expect(e.type, 'suggestion.skipped');
      expect(e.v, eventSchemaVersion);
      expect(e.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(folder.files.keys, ['Sasa/devices/linux-1/log-2026-11.jsonl']);
      expect(folder.files.values.single, '${e.toLine()}\n');
    });

    test('starts a new file each UTC month', () async {
      final log = logFor(folder, 'linux-1', clock);
      clock.set(z(2026, 11, 30, 23, 59));
      await log.append(skipA);
      clock.set(z(2026, 12, 1, 0, 1));
      await log.append(skipA);
      expect(folder.files.keys.toList()..sort(), [
        'Sasa/devices/linux-1/log-2026-11.jsonl',
        'Sasa/devices/linux-1/log-2026-12.jsonl',
      ]);
      expect((await log.load()).events, hasLength(2));
    });

    test('concurrent appends from one device all land intact', () async {
      final log = logFor(folder, 'linux-1', clock);
      await Future.wait([for (var i = 0; i < 100; i++) log.append(skipA)]);
      final snap = await log.load();
      expect(snap.events, hasLength(100));
      expect(snap.issues, isEmpty);
    });

    test('uses a custom root folder name', () async {
      final log = EventLog(
        folder: folder,
        deviceId: 'd',
        clock: clock,
        root: 'Test',
      );
      await log.append(skipA);
      expect(folder.files.keys.single, startsWith('Test/devices/d/'));
    });
  });

  group('tolerant reader', () {
    test(
      'a crash halfway through the last line loses only that line',
      () async {
        final log = logFor(folder, 'linux-1', clock);
        await log.append(skipA);
        await log.append(skipA);
        folder.corruptAppend(
          'Sasa/devices/linux-1/log-2026-11.jsonl',
          '{"id":"half-writ',
        );

        final snap = await logFor(folder, 'linux-1', clock).load();
        expect(snap.events, hasLength(2));
        expect(snap.state.skips, hasLength(2));
        expect(
          snap.issues.single.path,
          'Sasa/devices/linux-1/log-2026-11.jsonl',
        );
        expect(snap.issues.single.line, 3);
      },
    );

    test('the next append after a crash starts on a fresh line', () async {
      await logFor(folder, 'linux-1', clock).append(skipA);
      folder.corruptAppend(
        'Sasa/devices/linux-1/log-2026-11.jsonl',
        '{"id":"half',
      );
      // A new process (fresh EventLog) appends after the crash.
      final log = logFor(folder, 'linux-1', clock, seed: 2);
      await log.append(skipA);
      await log.append(skipA);
      final snap = await log.load();
      expect(snap.events, hasLength(3));
      expect(snap.issues, hasLength(1), reason: 'only the torn line is lost');
    });

    test('skips blank lines, CRLF endings and garbage lines', () async {
      final good = await logFor(folder, 'linux-1', clock).append(skipA);
      folder.corruptAppend(
        'Sasa/devices/linux-1/log-2026-11.jsonl',
        '\n\r\nnot json\n[1]\n${good.toLine().replaceFirst(good.id, 'other')}\r\n',
      );
      final snap = await logFor(folder, 'linux-1', clock).load();
      expect(snap.events.map((e) => e.id), unorderedEquals([good.id, 'other']));
      expect(snap.issues.map((i) => i.line), [4, 5]);
      expect(snap.issues.first.toString(), contains('log-2026-11.jsonl:4'));
    });

    test('a known type with bad data is reported and not applied', () async {
      final bad = LogEvent(
        id: 'bad',
        ts: clock.now(),
        device: 'linux-1',
        type: 'energy.checkin',
        v: 1,
        data: const {'energy': 'sleepy'},
      );
      await folder.append(
        'Sasa/devices/linux-1/log-2026-11.jsonl',
        '${bad.toLine()}\n',
      );
      final snap = await logFor(folder, 'linux-1', clock).load();
      expect(snap.events, hasLength(1), reason: 'kept, for future versions');
      expect(snap.state.energy, isEmpty);
      expect(snap.issues.single.reason, contains('energy'));
    });

    test('events from a newer app version are counted, not applied', () async {
      final newer = LogEvent(
        id: 'n',
        ts: clock.now(),
        device: 'android-1',
        type: 'energy.checkin',
        v: eventSchemaVersion + 1,
        data: const {'energy': 'high', 'confidence': 0.8},
      );
      await folder.append(
        'Sasa/devices/android-1/log-2026-11.jsonl',
        '${newer.toLine()}\n',
      );
      final snap = await logFor(folder, 'linux-1', clock).load();
      expect(snap.newerVersionEvents, 1);
      expect(snap.state.energy, isEmpty);
      expect(snap.issues, isEmpty);
    });

    test(
      'ignores files that are not logs and folders that are not devices',
      () async {
        await logFor(folder, 'linux-1', clock).append(skipA);
        await folder.write('Sasa/devices/linux-1/notes.txt', 'hello');
        await folder.write(
          'Sasa/devices/linux-1/.syncthing.log-2026-11.jsonl.tmp',
          'partial',
        );
        await folder.write('Sasa/devices/linux-1/~log-2026-11.jsonl', 'x');
        await folder.write('Sasa/devices/.stfolder/log-2026-11.jsonl', 'x');
        await folder.write('Sasa/devices/stray-file.jsonl', 'x');
        final snap = await logFor(folder, 'linux-1', clock).load();
        expect(snap.events, hasLength(1));
        expect(snap.issues, isEmpty);
        expect(snap.devices, ['linux-1']);
      },
    );

    test('a sync-conflict copy of a log adds nothing twice', () async {
      final log = logFor(folder, 'linux-1', clock);
      await log.append(skipA);
      await log.append(skipA);
      final main = folder.files['Sasa/devices/linux-1/log-2026-11.jsonl']!;
      await folder.write(
        'Sasa/devices/linux-1/'
        'log-2026-11.sync-conflict-20261108-101500-ABCDEFG.jsonl',
        main,
      );
      final snap = await log.load();
      expect(snap.events, hasLength(2));
      expect(snap.state.skips, hasLength(2));
    });

    test('an empty or missing folder loads as empty state', () async {
      final snap = await logFor(folder, 'linux-1', clock).load();
      expect(snap.events, isEmpty);
      expect(snap.state, AppState.empty);
      expect(snap.devices, isEmpty);
    });
  });

  group('two devices', () {
    test('interleaved writes to one shared folder merge by ts', () async {
      final laptop = logFor(folder, 'linux-1', clock, seed: 1);
      final phoneClock = FakeClock(
        z(2026, 11, 8, 9).add(const Duration(seconds: 30)),
      );
      final phone = logFor(folder, 'android-1', phoneClock, seed: 2);

      final writes = <Future<LogEvent>>[];
      for (var i = 0; i < 50; i++) {
        writes
          ..add(
            laptop.append(
              SuggestionSkipped(activityId: 'l$i', categoryId: 'c'),
            ),
          )
          ..add(
            phone.append(SuggestionSkipped(activityId: 'p$i', categoryId: 'c')),
          );
        clock.advance(const Duration(minutes: 1));
        phoneClock.advance(const Duration(minutes: 1));
      }
      await Future.wait(writes);

      // Each device only ever wrote to its own folder.
      expect(folder.files.keys.toList()..sort(), [
        'Sasa/devices/android-1/log-2026-11.jsonl',
        'Sasa/devices/linux-1/log-2026-11.jsonl',
      ]);
      for (final MapEntry(:key, :value) in folder.files.entries) {
        final owner = key.split('/')[2];
        for (final line in value.trim().split('\n')) {
          expect(LogEvent.fromLine(line).device, owner);
        }
      }

      final a = await laptop.load();
      final b = await phone.load();
      expect(a.events, hasLength(100));
      expect(a.state, b.state);
      expect(a.devices, ['android-1', 'linux-1']);
      // Merged order alternates laptop, phone, laptop, ...
      expect(a.events.take(4).map((e) => e.data['activityId']), [
        'l0',
        'p0',
        'l1',
        'p1',
      ]);
    });

    test(
      'separate replicas synced like Syncthing converge, never conflict',
      () async {
        final laptopFolder = MemorySyncFolder();
        final phoneFolder = MemorySyncFolder();
        final phoneClock = FakeClock(clock.now());
        final laptop = logFor(laptopFolder, 'linux-1', clock, seed: 1);
        final phone = logFor(phoneFolder, 'android-1', phoneClock, seed: 2);

        final start = clock.now();
        // Both devices work offline at the same time on one session each,
        // and the phone also completes the laptop's session after a sync.
        await laptop.append(
          SessionStarted(
            sessionId: 'sl',
            activityId: 'a',
            categoryId: 'research',
            plannedMin: 60,
            start: start,
          ),
        );
        await phone.append(const EnergyCheckin(energy: Energy.high));
        await phone.append(
          SessionStarted(
            sessionId: 'sp',
            activityId: 'b',
            categoryId: 'reading',
            plannedMin: 30,
            start: start,
          ),
        );
        clock.advance(const Duration(minutes: 30));
        phoneClock.advance(const Duration(minutes: 30));
        await phone.append(
          SessionCompleted(
            sessionId: 'sp',
            activityId: 'b',
            categoryId: 'reading',
            start: start,
            end: phoneClock.now(),
          ),
        );
        await laptop.append(skipA);

        // Sync both ways. A file is only ever copied from its owner.
        await syncDevice(laptopFolder, phoneFolder, 'linux-1');
        await syncDevice(phoneFolder, laptopFolder, 'android-1');

        clock.advance(const Duration(minutes: 30));
        await phone.append(
          SessionCompleted(
            sessionId: 'sl',
            activityId: 'a',
            categoryId: 'research',
            start: start,
            end: clock.now(),
          ),
        );
        await syncDevice(phoneFolder, laptopFolder, 'android-1');
        await syncDevice(laptopFolder, phoneFolder, 'linux-1');

        expect(laptopFolder.files, phoneFolder.files);
        final a = await laptop.load();
        final b = await phone.load();
        expect(a.state, b.state);
        expect(
          a.state.sessions.map((s) => s.id),
          unorderedEquals(['sl', 'sp']),
        );
        expect(a.state.activeSessions, isEmpty);
        expect(a.state.latestEnergy!.energy, Energy.high);
        expect(a.state.skips, hasLength(1));
      },
    );

    group('on disk', () {
      late Directory tmp;
      setUp(
        () async => tmp = await Directory.systemTemp.createTemp('sasa-el-'),
      );
      tearDown(() => tmp.delete(recursive: true));

      test('devices in other isolates and the same device in another process '
          'append at the same time without losing a line', () async {
        final path = tmp.path;
        // The second writer of linux-1 is a separate process, like the
        // Linux app and the `sasa` CLI on one machine.
        final other = Process.run(Platform.resolvedExecutable, [
          'run',
          'test/support/append_worker.dart',
          path,
          'linux-1',
          '3',
          '300',
        ]);
        final writers = [
          Isolate.run(() => appendMany(path, 'linux-1', 1, 300)),
          Isolate.run(() => appendMany(path, 'android-1', 2, 300)),
        ];
        // Start everyone at once, after the process is up (it polls too).
        await Future<void>.delayed(const Duration(seconds: 2));
        File('$path/.go').createSync();
        await Future.wait(writers);
        final result = await other;
        expect(result.exitCode, 0, reason: '${result.stderr}');

        final snap = await EventLog(
          folder: IoSyncFolder(path),
          deviceId: 'linux-1',
          clock: clock,
        ).load();
        expect(snap.issues, isEmpty);
        expect(snap.events, hasLength(900));
        expect(snap.state.skips, hasLength(900));
        expect(snap.devices, ['android-1', 'linux-1']);

        // The two linux-1 writers really ran at the same time: their lines
        // are interleaved in the one file, not two blocks.
        final writersInOrder =
            File('$path/Sasa/devices/linux-1/log-2026-11.jsonl')
                .readAsLinesSync()
                .map(
                  (l) => (LogEvent.fromLine(l).data['activityId']! as String)
                      .split('-')[2],
                )
                .toList();
        var switches = 0;
        for (var i = 1; i < writersInOrder.length; i++) {
          if (writersInOrder[i] != writersInOrder[i - 1]) switches++;
        }
        expect(switches, greaterThan(1));
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('a torn line written by a killed process is tolerated', () async {
        final f = IoSyncFolder(tmp.path);
        final log = logFor(f, 'linux-1', clock);
        await log.append(skipA);
        File('${tmp.path}/Sasa/devices/linux-1/log-2026-11.jsonl')
            .writeAsStringSync('{"id":"x","ts":"2026-', mode: FileMode.append);
        final again = logFor(f, 'linux-1', clock, seed: 9);
        await again.append(skipA);
        final snap = await again.load();
        expect(snap.events, hasLength(2));
        expect(snap.issues, hasLength(1));
      });
    });
  });
}
