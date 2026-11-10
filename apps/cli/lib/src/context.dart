import 'dart:io';

import 'package:args/args.dart';
import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notifier.dart';
import 'secrets.dart';

/// Exit code for missing or bad local setup (`sysexits.h` EX_CONFIG).
const int exitConfig = 78;

/// Exit code when a service the command needs failed (`sysexits.h`
/// EX_UNAVAILABLE), e.g. no desktop notification server.
const int exitUnavailable = 69;

/// Builds the calendar source for a CalDAV account.
typedef SourceFactory = CalendarSource Function(
  CalDavAccount account,
  tz.Location zone,
);

/// Everything commands get from outside, injectable for tests.
final class CliServices {
  CliServices({
    required this.out,
    required this.err,
    required this.env,
    required this.keyring,
    required this.clock,
    required this.notifier,
    required this.sourceFor,
    required this.run,
    required this.executable,
  });

  final StringSink out;
  final StringSink err;
  final Map<String, String> env;
  final Keyring keyring;
  final Clock clock;
  final DesktopNotifier notifier;
  final SourceFactory sourceFor;

  /// Runs `systemctl`.
  final RunProcess run;

  /// Path of the running `sasa` executable (the Dart VM under `dart run`).
  final String executable;
}

/// The synced folder this machine uses, opened.
final class FolderContext {
  FolderContext(this.path, this.device, this.folder);

  final String path;
  final DeviceInfo device;
  final SasaFolder folder;
}

/// Opens the synced folder from `--folder`, `SASA_FOLDER` or `device.json`;
/// null (after explaining on [err]) when there is none.
Future<FolderContext?> openFolder(
  ArgResults global,
  Map<String, String> env,
  StringSink err,
) async {
  final deviceFilePath =
      global.option('device-file') ?? DeviceFile.defaultPath(env);
  var info = const DeviceInfo();
  if (deviceFilePath != null) {
    try {
      info = await DeviceFile(deviceFilePath).read();
    } on FormatException catch (e) {
      err.writeln('Cannot read $deviceFilePath: ${e.message}');
      return null;
    }
  }
  final path = global.option('folder') ?? env['SASA_FOLDER'] ?? info.syncFolder;
  if (path == null) {
    err.writeln(
      'No synced folder set. Pass --folder <path>, set SASA_FOLDER, or '
      'choose one in the Sasa app on this machine.',
    );
    return null;
  }
  if (!Directory(path).existsSync()) {
    err.writeln('Synced folder $path does not exist.');
    return null;
  }
  return FolderContext(path, info, SasaFolder(IoSyncFolder(path)));
}

/// `config.json`, or the defaults when there is none yet (nothing is
/// written); null (after explaining on [err]) when it cannot be read.
Future<AppConfig?> loadConfig(
  FolderContext ctx,
  Clock clock,
  StringSink err,
) async {
  try {
    return await ctx.folder.loadConfig() ?? AppConfig.defaults(clock: clock);
  } on FormatException catch (e) {
    err.writeln('config.json cannot be read (${e.message}).');
  } on UnsupportedConfigVersion catch (e) {
    err.writeln('$e');
  }
  return null;
}

/// The configured zone; null (after explaining on [err]) when unknown.
tz.Location? zoneOf(AppConfig config, StringSink err) {
  try {
    return locationFor(config.timeZone);
  } on tz.LocationNotFoundException {
    err.writeln('Unknown time zone "${config.timeZone}" in config.json.');
    return null;
  }
}
