import 'dart:io';

import 'package:sasa_cli/sasa_cli.dart';
import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'fakes.dart';

final paris = locationFor('Europe/Paris');

DateTime p(int y, int m, int d, [int h = 0, int min = 0]) =>
    utcInstant(tz.TZDateTime(paris, y, m, d, h, min));

void main() {
  late Directory tmp;
  late String sync;
  late Map<String, String> env;
  late FakeClock clock;
  late FakeNotifier notifier;
  late FakeSource source;
  CalDavAccount? sourceAccount;

  Future<void> writeConfig(AppConfig Function(AppConfig) edit) async {
    final folder = SasaFolder(IoSyncFolder(sync));
    await folder.saveConfig(edit(AppConfig.defaults(clock: clock)));
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sasa-cli-');
    sync = '${tmp.path}/Sync';
    Directory(sync).createSync();
    env = {
      'XDG_CONFIG_HOME': '${tmp.path}/config',
      'SASA_CALDAV_URL': 'https://dav.example.org/',
      'SASA_CALDAV_USER': 'me',
      'SASA_CALDAV_PASSWORD': 'hunter2',
    };
    clock = FakeClock(p(2026, 11, 9, 7, 30)); // Monday
    notifier = FakeNotifier();
    sourceAccount = null;
    source = FakeSource(
      events: [
        CalEvent(
          uid: 'tp',
          title: 'Networks lab',
          start: p(2026, 11, 9, 10, 30),
          end: p(2026, 11, 9, 12, 30),
          allDay: false,
          busy: true,
          calendarName: 'Cours',
        ),
      ],
      tasks: [
        TaskItem(
          uid: 'r',
          title: 'review for X',
          listName: 'PhD',
          tags: const [],
          due: p(2026, 11, 9, 18),
          completed: false,
        ),
      ],
    );
    await writeConfig(
      (c) => c.copyWith(
        rules: const [
          MappingRule(
            field: MatchField.calendar,
            pattern: 'Cours',
            categoryId: 'teaching',
          ),
        ],
      ),
    );
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<(int, String, String)> run(
    List<String> args, {
    CalendarSource? from,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runSasa(
      ['--folder', sync, ...args],
      out,
      err,
      env: env,
      keyring: () async => null,
      clock: clock,
      notifier: notifier,
      sourceFor: (account, zone) {
        sourceAccount = account;
        return from ?? source;
      },
    );
    return (code, '$out', '$err');
  }

  test('prints the brief and shows it as a notification', () async {
    final (code, out, err) = await run(['brief']);
    expect(err, isEmpty);
    expect(code, 0);
    const title = 'Sasa! Mon 9 Nov — 1 event · 8 h 50 free';
    expect(out, startsWith('$title\n08:00–10:25  free (2 h 25)\n'));
    expect(out, contains('10:30–12:30  Networks lab (Teaching)'));
    expect(out, contains('Due: review for X (today)'));
    expect(notifier.shown, hasLength(1));
    expect(notifier.shown.single.$1, title);
    expect(notifier.shown.single.$2, isNot(contains(title)));
    expect(notifier.shown.single.$2, contains('Networks lab'));
    expect(sourceAccount?.username, 'me');
    expect(out + err, isNot(contains('hunter2')));
  });

  test('--no-notify only prints', () async {
    final (code, out, _) = await run(['brief', '--no-notify']);
    expect(code, 0);
    expect(out, startsWith('Sasa! Mon 9 Nov'));
    expect(notifier.shown, isEmpty);
  });

  group('--scheduled', () {
    test('skips before the brief time', () async {
      clock.set(p(2026, 11, 9, 7, 29));
      final (code, out, _) = await run(['brief', '--scheduled']);
      expect(code, 0);
      expect(out, 'No brief due now (07:30 on weekdays).\n');
      expect(notifier.shown, isEmpty);
    });

    test('sends from the brief time on', () async {
      clock.set(p(2026, 11, 9, 9));
      final (code, _, _) = await run(['brief', '--scheduled']);
      expect(code, 0);
      expect(notifier.shown, hasLength(1));
    });

    test('skips a brief that is too late, or on the weekend', () async {
      clock.set(p(2026, 11, 9, 11));
      expect((await run(['brief', '--scheduled'])).$2, startsWith('No brief'));
      clock.set(p(2026, 11, 14, 7, 30));
      expect((await run(['brief', '--scheduled'])).$2, startsWith('No brief'));
      expect(notifier.shown, isEmpty);
    });

    test('says when the brief is off', () async {
      await writeConfig(
        (c) => c.copyWith(brief: c.brief.copyWith(enabled: false)),
      );
      final (code, out, _) = await run(['brief', '--scheduled']);
      expect(code, 0);
      expect(out, 'The morning brief is off.\n');
      expect(notifier.shown, isEmpty);
    });

    test('a manual brief is sent even when off', () async {
      await writeConfig(
        (c) => c.copyWith(brief: c.brief.copyWith(enabled: false)),
      );
      final (code, _, _) = await run(['brief']);
      expect(code, 0);
      expect(notifier.shown, hasLength(1));
    });
  });

  test('without a CalDAV account the brief says so', () async {
    env.removeWhere((k, _) => k.startsWith('SASA_CALDAV'));
    final (code, out, err) = await run(['brief']);
    expect(code, 0);
    expect(err, contains('No CalDAV account'));
    expect(out, startsWith('Sasa! Mon 9 Nov — calendar unavailable\n'));
    expect(notifier.shown, hasLength(1));
  });

  test('a calendar error still sends the brief, with tasks', () async {
    final (code, out, err) = await run(['brief'], from: _FailingEvents(source));
    expect(code, 0);
    expect(err, contains('Could not load events'));
    expect(out, contains('calendar unavailable'));
    expect(out, contains('Could not load your calendar.'));
    expect(out, contains('Due: review for X (today)'));
  });

  test('no notification server is an error after printing', () async {
    notifier.fail = true;
    final (code, out, err) = await run(['brief']);
    expect(code, exitUnavailable);
    expect(out, startsWith('Sasa!'));
    expect(err, contains('Could not show the notification'));
  });

  test('without config.json uses the defaults and writes nothing', () async {
    File('$sync/Sasa/config.json').deleteSync();
    final (code, out, _) = await run(['brief', '--no-notify']);
    expect(code, 0);
    expect(out, contains('Networks lab\n'), reason: 'no rule: unclassified');
    expect(File('$sync/Sasa/config.json').existsSync(), isFalse);
  });

  test('a corrupt config.json is a config error', () async {
    File('$sync/Sasa/config.json').writeAsStringSync('{');
    final (code, _, err) = await run(['brief']);
    expect(code, exitConfig);
    expect(err, contains('config.json cannot be read'));
  });
}

final class _FailingEvents implements CalendarSource {
  _FailingEvents(this.inner);
  final CalendarSource inner;

  @override
  Future<List<CalEvent>> events(DateTime from, DateTime to) async =>
      throw const SourceUnavailable('server down');

  @override
  Future<List<TaskItem>> tasks() => inner.tasks();
}
