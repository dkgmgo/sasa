import 'dart:io';

import 'package:sasa_cli/sasa_cli.dart';
import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  final weekdays = BriefSettings.defaults();

  group('unit text', () {
    test('OnCalendar follows the brief days, time and zone', () {
      expect(
        briefOnCalendar(weekdays, 'Europe/Paris'),
        'Mon..Fri *-*-* 07:30:00 Europe/Paris',
      );
      expect(
        briefOnCalendar(
          weekdays.copyWith(
            time: const LocalTime(6, 5),
            days: BriefDays.everyDay,
          ),
          'Africa/Nairobi',
        ),
        '*-*-* 06:05:00 Africa/Nairobi',
      );
    });

    test('ExecStart words are quoted for systemd', () {
      expect(systemdQuote('/usr/bin/sasa'), '/usr/bin/sasa');
      expect(systemdQuote('/home/me/My Sync'), '"/home/me/My Sync"');
      expect(systemdQuote('100%'), '100%%');
      expect(systemdQuote(r'$HOME'), r'$$HOME');
      expect(systemdQuote(r'a"b\c'), r'"a\"b\\c"');
      expect(systemdQuote(''), '""');
    });

    test('four units: the brief runs --scheduled, the tick every 15 min', () {
      final units = systemdUnits(
        command: ['/opt/sasa', '--folder', '/home/me/My Sync'],
        unitDir: '/home/me/.config/systemd/user',
        brief: weekdays,
        timeZone: 'Europe/Paris',
      );
      expect(units.keys, [briefService, briefTimer, tickService, tickTimer]);
      expect(
        units[briefService],
        contains(
          'ExecStart=/opt/sasa --folder "/home/me/My Sync" brief --scheduled\n',
        ),
      );
      expect(units[briefService], contains('Type=oneshot'));
      expect(
        units[briefTimer],
        contains('OnCalendar=Mon..Fri *-*-* 07:30:00 Europe/Paris\n'),
      );
      expect(units[briefTimer], contains('Persistent=true'));
      expect(units[briefTimer], contains('WantedBy=timers.target'));
      expect(
        units[tickService],
        contains(
          'ExecStart=/opt/sasa --folder "/home/me/My Sync" tick '
          '--unit-dir /home/me/.config/systemd/user\n',
        ),
      );
      expect(units[tickTimer], contains('OnCalendar=*:0/15\n'));
    });

    test('unit dir from XDG_CONFIG_HOME, else HOME', () {
      expect(
        systemdUserUnitDir({'XDG_CONFIG_HOME': '/x', 'HOME': '/h'}),
        '/x/systemd/user',
      );
      expect(systemdUserUnitDir({'HOME': '/h'}), '/h/.config/systemd/user');
      expect(systemdUserUnitDir({}), isNull);
    });
  });

  group('commands', () {
    late Directory tmp;
    late String sync;
    late String unitDir;
    late Map<String, String> env;
    late List<List<String>> systemctl;
    late int systemctlExit;
    late bool timerActive;
    final clock = FakeClock(DateTime.utc(2026, 11, 9, 6));

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sasa-cli-');
      sync = '${tmp.path}/My Sync';
      Directory(sync).createSync();
      unitDir = '${tmp.path}/config/systemd/user';
      env = {'XDG_CONFIG_HOME': '${tmp.path}/config'};
      systemctl = [];
      systemctlExit = 0;
      timerActive = true;
      await SasaFolder(IoSyncFolder(sync))
          .saveConfig(AppConfig.defaults(clock: clock));
    });
    tearDown(() => tmp.delete(recursive: true));

    Future<(int, String, String)> run(
      List<String> args, {
      String executable = '/opt/sasa/sasa',
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
        notifier: FakeNotifier(),
        run: (exe, a) async {
          systemctl.add([exe, ...a]);
          // `is-active` exits 3 for an inactive or unknown unit.
          if (a.contains('is-active')) {
            return ProcessResult(0, timerActive ? 0 : 3, '', '');
          }
          return ProcessResult(0, systemctlExit, '', 'boom');
        },
        executable: executable,
      );
      return (code, '$out', '$err');
    }

    Future<void> setBrief(BriefSettings b) async {
      final f = SasaFolder(IoSyncFolder(sync));
      await f.saveConfig((await f.loadConfig())!.copyWith(brief: b));
    }

    String unit(String name) => File('$unitDir/$name').readAsStringSync();

    test(
      'install-timers writes the units and explains how to enable',
      () async {
        final (code, out, err) = await run(['install-timers']);
        expect(err, isEmpty);
        expect(code, 0);
        for (final u in [briefService, briefTimer, tickService, tickTimer]) {
          expect(out, contains('Wrote $unitDir/$u'));
        }
        expect(
          unit(briefService),
          contains(
            'ExecStart=/opt/sasa/sasa --folder "$sync" brief --scheduled',
          ),
        );
        expect(
          unit(briefTimer),
          contains('OnCalendar=Mon..Fri *-*-* 07:30:00'),
        );
        expect(out, contains('systemctl --user enable --now'));
        expect(systemctl, isEmpty, reason: 'only prints how to enable');
      },
    );

    test('install-timers --dry-run writes nothing', () async {
      final (code, out, _) = await run(['install-timers', '--dry-run']);
      expect(code, 0);
      expect(out, contains('# $unitDir/$briefTimer'));
      expect(out, contains('OnCalendar=Mon..Fri'));
      expect(Directory(unitDir).existsSync(), isFalse);
    });

    test('install-timers under `dart run` asks for a compiled sasa', () async {
      final (code, _, err) = await run([
        'install-timers',
      ], executable: '/usr/lib/dart/bin/dart');
      expect(code, exitConfig);
      expect(err, contains('dart compile exe'));
      final (code2, _, _) = await run([
        'install-timers',
        '--exec',
        '/usr/local/bin/sasa',
      ], executable: '/usr/lib/dart/bin/dart');
      expect(code2, 0);
      expect(unit(tickService), contains('ExecStart=/usr/local/bin/sasa '));
    });

    test('tick without installed timers does nothing', () async {
      final (code, out, _) = await run(['tick']);
      expect(code, 0);
      expect(out, contains('not installed'));
      expect(systemctl, isEmpty);
    });

    test('tick leaves an up-to-date timer alone', () async {
      await run(['install-timers']);
      final (code, out, _) = await run(['tick']);
      expect(code, 0);
      expect(out, contains('up to date'));
      expect(systemctl, isEmpty);
    });

    test('tick rewrites the timer when the brief time changed', () async {
      await run(['install-timers']);
      final service = unit(briefService);
      await setBrief(
        BriefSettings(time: const LocalTime(8, 15), days: BriefDays.everyDay),
      );
      final (code, out, _) = await run(['tick']);
      expect(code, 0);
      expect(out, contains('Brief timer updated: 08:15 every day'));
      expect(unit(briefTimer), contains('OnCalendar=*-*-* 08:15:00 Europe/'));
      expect(unit(briefService), service, reason: 'only the timer changes');
      expect(systemctl, [
        ['systemctl', '--user', 'daemon-reload'],
        ['systemctl', '--user', 'is-active', '--quiet', briefTimer],
        ['systemctl', '--user', 'restart', briefTimer],
      ]);
      // A second tick finds it up to date.
      systemctl.clear();
      expect((await run(['tick'])).$2, contains('up to date'));
      expect(systemctl, isEmpty);
    });

    test('tick does not start a timer that is off or not loaded', () async {
      await run(['install-timers']);
      await setBrief(BriefSettings(time: const LocalTime(9, 0)));
      timerActive = false;
      final (code, out, err) = await run(['tick']);
      expect(err, isEmpty);
      expect(code, 0);
      expect(out, contains('Brief timer updated'));
      expect(systemctl.last, [
        'systemctl',
        '--user',
        'is-active',
        '--quiet',
        briefTimer,
      ]);
    });

    test('tick reports a failing systemctl', () async {
      await run(['install-timers']);
      await setBrief(BriefSettings(time: const LocalTime(9, 0)));
      systemctlExit = 1;
      final (code, _, err) = await run(['tick']);
      expect(code, exitUnavailable);
      expect(err, contains('daemon-reload failed'));
    });
  });
}
