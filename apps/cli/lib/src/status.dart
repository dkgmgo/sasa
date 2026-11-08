import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';

import 'secrets.dart';

/// Exit code for missing or bad local setup (`sysexits.h` EX_CONFIG).
const int exitConfig = 78;

/// `sasa status`: what this machine would read and write. Read-only.
final class StatusCommand extends Command<int> {
  StatusCommand({
    required this.out,
    required this.err,
    required this.env,
    required this.keyring,
  });

  final StringSink out;
  final StringSink err;
  final Map<String, String> env;
  final Keyring keyring;

  @override
  String get name => 'status';

  @override
  String get description =>
      'Show the synced folder, device, event log, config conflicts and '
      'whether a CalDAV account is set (never the password).';

  @override
  Future<int> run() async {
    final g = globalResults!;
    final deviceFilePath =
        g.option('device-file') ?? DeviceFile.defaultPath(env);
    var info = const DeviceInfo();
    if (deviceFilePath != null) {
      try {
        info = await DeviceFile(deviceFilePath).read();
      } on FormatException catch (e) {
        err.writeln('Cannot read $deviceFilePath: ${e.message}');
        return exitConfig;
      }
    }
    final folderPath =
        g.option('folder') ?? env['SASA_FOLDER'] ?? info.syncFolder;
    if (folderPath == null) {
      err.writeln(
        'No synced folder set. Pass --folder <path>, set SASA_FOLDER, or '
        'choose one in the Sasa app on this machine.',
      );
      return exitConfig;
    }
    if (!Directory(folderPath).existsSync()) {
      err.writeln('Synced folder $folderPath does not exist.');
      return exitConfig;
    }

    out.writeln('Device: ${info.deviceId ?? 'not set'}');
    out.writeln('Folder: $folderPath');

    final sasa = SasaFolder(IoSyncFolder(folderPath));
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
