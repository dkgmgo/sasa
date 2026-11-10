import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:sasa_caldav/sasa_caldav.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'brief_command.dart';
import 'context.dart';
import 'notifier.dart';
import 'secrets.dart';
import 'status.dart';
import 'timer_commands.dart';

/// Exit code for invalid usage (same convention as `sysexits.h` EX_USAGE).
const int exitUsage = 64;

/// Exit code used when a command exists but is not implemented yet.
const int exitNotImplemented = 3;

/// Runs the `sasa` CLI with [arguments], writing to [out] and [err].
///
/// Everything from outside is injectable for tests: [env] defaults to the
/// process environment, [keyring] to libsecret via `secret-tool`, [clock] to
/// the system clock, [notifier] to D-Bus, [sourceFor] to CalDAV, [run] to
/// [Process.run] and [executable] to this process's executable. Returns the
/// exit code.
Future<int> runSasa(
  List<String> arguments,
  StringSink out,
  StringSink err, {
  Map<String, String>? env,
  Keyring? keyring,
  Clock? clock,
  DesktopNotifier? notifier,
  SourceFactory? sourceFor,
  RunProcess? run,
  String? executable,
}) async {
  final s = CliServices(
    out: out,
    err: err,
    env: env ?? Platform.environment,
    keyring: keyring ?? secretToolKeyring(),
    clock: clock ?? FunctionClock(DateTime.now),
    notifier: notifier ?? DbusNotifier(),
    sourceFor: sourceFor ?? calDavSource,
    run: run ?? Process.run,
    executable: executable ?? Platform.resolvedExecutable,
  );
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
        ..addCommand(StatusCommand(s))
        ..addCommand(BriefCommand(s))
        ..addCommand(TickCommand(s))
        ..addCommand(InstallTimersCommand(s))
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

/// Shared HTTP client for CalDAV; closed by [closeHttp].
http.Client? _http;

/// [SourceFactory] for a real CalDAV server.
CalendarSource calDavSource(CalDavAccount account, tz.Location zone) =>
    CalDavSource(
      client: CalDavClient(
        baseUri: account.url,
        httpClient: _http ??= http.Client(),
        credentials: CalDavCredentials(account.username, account.password),
      ),
      zones: ZoneResolver(zone),
    );

/// Closes kept-alive connections, so the process can exit at once.
void closeHttp() {
  _http?.close();
  _http = null;
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
