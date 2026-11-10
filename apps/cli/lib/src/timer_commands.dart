import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:sasa_core/sasa_core.dart';

import 'context.dart';
import 'timers.dart';

/// Global options passed on to the timers' `ExecStart=`, as absolute paths.
const _forwarded = ['folder', 'device-file', 'secrets-file'];

/// `sasa install-timers`: writes the systemd user units and explains how to
/// enable them. Does not run `systemctl` itself.
final class InstallTimersCommand extends Command<int> {
  InstallTimersCommand(this.s) {
    argParser
      ..addOption(
        'exec',
        help:
            'The sasa executable the timers run. Default: this one, when '
            'compiled (dart compile exe).',
        valueHelp: 'path',
      )
      ..addOption(
        'unit-dir',
        help: r'Default: $XDG_CONFIG_HOME/systemd/user.',
        valueHelp: 'path',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the units instead of writing them.',
      );
  }

  final CliServices s;

  @override
  String get name => 'install-timers';

  @override
  String get description =>
      'Write systemd user timers for the brief (time from config.json) and '
      'the 15-minute tick.';

  @override
  Future<int> run() async {
    final a = argResults!;
    final g = globalResults!;
    final exec = a.option('exec') ?? _compiledExecutable(s.executable);
    if (exec == null) {
      s.err.writeln(
        'Running under `dart run`: the timers need a compiled sasa. Build '
        'it with\n'
        '  dart compile exe apps/cli/bin/sasa.dart -o ~/.local/bin/sasa\n'
        'then run `~/.local/bin/sasa install-timers`, or pass --exec.',
      );
      return exitConfig;
    }
    final unitDir = a.option('unit-dir') ?? systemdUserUnitDir(s.env);
    if (unitDir == null) {
      s.err.writeln('Cannot find the systemd user unit dir: pass --unit-dir.');
      return exitConfig;
    }
    final ctx = await openFolder(g, s.env, s.err);
    if (ctx == null) return exitConfig;
    final config = await loadConfig(ctx, s.clock, s.err);
    if (config == null || zoneOf(config, s.err) == null) return exitConfig;

    final command = [
      File(exec).absolute.path,
      for (final o in _forwarded)
        if (g.option(o) case final v?) ...['--$o', File(v).absolute.path],
    ];
    final units = systemdUnits(
      command: command,
      unitDir: Directory(unitDir).absolute.path,
      brief: config.brief,
      timeZone: config.timeZone,
    );
    if (a.flag('dry-run')) {
      for (final MapEntry(:key, :value) in units.entries) {
        s.out
          ..writeln('# $unitDir/$key')
          ..writeln(value);
      }
      return 0;
    }
    Directory(unitDir).createSync(recursive: true);
    for (final MapEntry(:key, :value) in units.entries) {
      File('$unitDir/$key').writeAsStringSync(value);
      s.out.writeln('Wrote $unitDir/$key');
    }
    s.out
      ..writeln()
      ..writeln(
        'Brief: ${describeBrief(config.brief)} '
        '(${briefOnCalendar(config.brief, config.timeZone)}).',
      )
      ..writeln('Enable both timers with:')
      ..writeln('  systemctl --user daemon-reload')
      ..writeln('  systemctl --user enable --now $briefTimer $tickTimer')
      ..writeln('Check them with `systemctl --user list-timers \'sasa-*\'`.')
      ..writeln(
        '`sasa tick` keeps the brief time in line with config.json from then '
        'on.',
      );
    return 0;
  }

  static String? _compiledExecutable(String path) {
    final base = path.split('/').last;
    return base == 'dart' || base == 'dart.exe' || base == 'dartvm'
        ? null
        : path;
  }
}

/// `sasa tick`: the 15-minute background job. For now it keeps the brief
/// timer in line with `config.json` (the brief time may have been changed
/// on another device); due nudges and reports come later.
final class TickCommand extends Command<int> {
  TickCommand(this.s) {
    argParser.addOption(
      'unit-dir',
      help:
          r'Where the timers are installed. Default: $XDG_CONFIG_HOME/'
          'systemd/user.',
      valueHelp: 'path',
    );
  }

  final CliServices s;

  @override
  String get name => 'tick';

  @override
  String get description =>
      'Run due background work: keep the brief timer in line with '
      'config.json.';

  @override
  Future<int> run() async {
    final ctx = await openFolder(globalResults!, s.env, s.err);
    if (ctx == null) return exitConfig;
    final config = await loadConfig(ctx, s.clock, s.err);
    if (config == null || zoneOf(config, s.err) == null) return exitConfig;

    final unitDir = argResults!.option('unit-dir') ?? systemdUserUnitDir(s.env);
    final timer = unitDir == null ? null : File('$unitDir/$briefTimer');
    if (timer == null || !timer.existsSync()) {
      s.out.writeln('Brief timer not installed (run `sasa install-timers`).');
      return 0;
    }
    final wanted = briefTimerUnit(config.brief, config.timeZone);
    if (timer.readAsStringSync() == wanted) {
      s.out.writeln('Brief timer up to date.');
      return 0;
    }
    timer.writeAsStringSync(wanted);
    s.out.writeln(
      'Brief timer updated: ${describeBrief(config.brief)} '
      '(${briefOnCalendar(config.brief, config.timeZone)}).',
    );
    try {
      if (!await _systemctl(['daemon-reload'])) return exitUnavailable;
      // Only a running timer is restarted: one that is disabled, or not
      // loaded by systemd (another unit dir), stays as it is.
      final active = await s.run('systemctl', [
        '--user',
        'is-active',
        '--quiet',
        briefTimer,
      ]);
      if (active.exitCode == 0 && !await _systemctl(['restart', briefTimer])) {
        return exitUnavailable;
      }
    } on ProcessException catch (e) {
      s.err.writeln('Cannot run systemctl: ${e.message}');
      return exitUnavailable;
    }
    return 0;
  }

  /// Runs `systemctl --user [args]`; false (after explaining) on failure.
  Future<bool> _systemctl(List<String> args) async {
    final r = await s.run('systemctl', ['--user', ...args]);
    if (r.exitCode == 0) return true;
    s.err.writeln('systemctl ${args.join(' ')} failed: ${r.stderr}');
    return false;
  }
}
