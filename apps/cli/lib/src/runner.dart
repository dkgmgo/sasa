import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:sasa_core/sasa_core.dart';

import 'secrets.dart';
import 'status.dart';

/// Exit code used when a command exists but is not implemented yet.
const int exitNotImplemented = 3;

/// Exit code for invalid usage (same convention as `sysexits.h` EX_USAGE).
const int exitUsage = 64;

/// Runs the `sasa` CLI with [arguments], writing to [out] and [err].
///
/// [env] defaults to the process environment and [keyring] to libsecret via
/// `secret-tool`. Returns the exit code.
Future<int> runSasa(
  List<String> arguments,
  StringSink out,
  StringSink err, {
  Map<String, String>? env,
  Keyring? keyring,
}) async {
  final runner =
      CommandRunner<int>('sasa', 'Sasa, a local-first day organiser.')
        ..argParser.addOption(
          'folder',
          help:
              'Synced folder (the one containing Sasa/). Default: '
              r'$SASA_FOLDER, then the folder chosen in the app.',
          valueHelp: 'path',
        )
        ..argParser.addOption(
          'device-file',
          help: r'Default: $XDG_CONFIG_HOME/sasa/device.json.',
          valueHelp: 'path',
        )
        ..argParser.addOption(
          'secrets-file',
          help:
              'Env file with SASA_CALDAV_URL/USER/PASSWORD, used when the '
              r'variables are not set. Default: $XDG_CONFIG_HOME/sasa/'
              'secrets.env. Must not be inside the synced folder.',
          valueHelp: 'path',
        )
        ..addCommand(
          StatusCommand(
            out: out,
            err: err,
            env: env ?? Platform.environment,
            keyring: keyring ?? secretToolKeyring(),
          ),
        )
        ..addCommand(
          _StubCommand('brief', 'Render and send the morning brief.', out),
        )
        ..addCommand(
          _StubCommand(
            'tick',
            'Run due background work (nudges, reports).',
            out,
          ),
        )
        ..addCommand(
          _StubCommand('suggest', 'Print the top suggestion for now.', out),
        )
        ..addCommand(
          _StubCommand('report', 'Generate the weekly report.', out),
        );

  try {
    final code = await runner.run(arguments);
    return code ?? 0;
  } on UsageException catch (e) {
    err.writeln(e);
    return exitUsage;
  }
}

class _StubCommand extends Command<int> {
  _StubCommand(this.name, this.description, this._out);

  @override
  final String name;

  @override
  final String description;

  final StringSink _out;

  @override
  int run() {
    _out.writeln(
      '${placeholderMessage()} `sasa $name` is not implemented yet.',
    );
    return exitNotImplemented;
  }
}
