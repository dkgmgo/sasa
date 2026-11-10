import 'package:args/command_runner.dart';
import 'package:sasa_core/sasa_core.dart';

import 'context.dart';
import 'secrets.dart';

/// `sasa status`: what this machine would read and write. Read-only.
final class StatusCommand extends Command<int> {
  StatusCommand(this.s);

  final CliServices s;

  StringSink get out => s.out;
  StringSink get err => s.err;
  Map<String, String> get env => s.env;
  Keyring get keyring => s.keyring;

  @override
  String get name => 'status';

  @override
  String get description =>
      'Show the synced folder, device, event log, config conflicts and '
      'whether a CalDAV account is set (never the password).';

  @override
  Future<int> run() async {
    final g = globalResults!;
    final ctx = await openFolder(g, env, err);
    if (ctx == null) return exitConfig;
    final info = ctx.device;
    final folderPath = ctx.path;

    out.writeln('Device: ${info.deviceId ?? 'not set'}');
    out.writeln('Folder: $folderPath');

    final sasa = ctx.folder;
    final snap = await sasa
        .eventLog(deviceId: info.deviceId ?? 'cli', clock: _NoClock())
        .load();
    final devices = snap.devices;
    out.writeln(
      'Events: ${snap.events.length} from ${devices.length} '
      'device${devices.length == 1 ? '' : 's'}'
      '${devices.isEmpty ? '' : ' (${devices.join(', ')})'}',
    );
    if (snap.issues.isNotEmpty) {
      final n = snap.issues.length;
      out.writeln('  $n unreadable line${n == 1 ? '' : 's'} (skipped):');
      for (final i in snap.issues.take(5)) {
        out.writeln('    $i');
      }
    }
    if (snap.newerVersionEvents > 0) {
      out.writeln(
        '  ${snap.newerVersionEvents} events from a newer Sasa version '
        'were not read; update this machine.',
      );
    }

    try {
      final config = await sasa.loadConfig();
      out.writeln(
        config == null
            ? 'Config: none yet'
            : 'Config: ${config.categories.length} categories, updated '
                  '${config.updatedAt.toIso8601String()}',
      );
    } on FormatException catch (e) {
      out.writeln('Config: unreadable (${e.message})');
    } on UnsupportedConfigVersion catch (e) {
      out.writeln('Config: $e');
    }
    final conflicts = await sasa.configConflicts();
    if (conflicts.isNotEmpty) {
      out.writeln('  ${conflicts.length} conflict copies of config.json:');
      for (final c in conflicts) {
        out.writeln('    ${c.name}');
      }
    }

    final secrets = await findCalDavAccount(
      env: env,
      envFilePath: g.option('secrets-file') ?? defaultEnvFile(env),
      keyring: keyring,
      syncFolder: folderPath,
    );
    secrets.warnings.forEach(err.writeln);
    final a = secrets.account;
    out.writeln(
      a == null
          ? 'CalDAV: not configured'
          : 'CalDAV: ${a.username} @ ${a.url} (${secrets.source})',
    );
    return 0;
  }
}

/// Loading never stamps events; appending is not allowed from `status`.
final class _NoClock implements Clock {
  @override
  DateTime now() => throw StateError('status is read-only');
}
