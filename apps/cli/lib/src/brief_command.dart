import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'context.dart';
import 'notifier.dart';
import 'secrets.dart';

/// How long the calendar server gets to answer.
const Duration sourceTimeout = Duration(seconds: 30);

/// `sasa brief`: renders today's brief, prints it and shows it as a desktop
/// notification. Reads the calendar only.
final class BriefCommand extends Command<int> {
  BriefCommand(this.s) {
    argParser
      ..addFlag(
        'scheduled',
        negatable: false,
        help:
            'Started by the timer: send only on a brief day, from the brief '
            'time until ${briefLateLimit.inHours} h later.',
      )
      ..addFlag(
        'notify',
        defaultsTo: true,
        help: 'Show a desktop notification (--no-notify only prints).',
      );
  }

  final CliServices s;

  @override
  String get name => 'brief';

  @override
  String get description =>
      'Render the morning brief, print it and send it as a desktop '
      'notification.';

  @override
  Future<int> run() async {
    final ctx = await openFolder(globalResults!, s.env, s.err);
    if (ctx == null) return exitConfig;
    final config = await loadConfig(ctx, s.clock, s.err);
    if (config == null) return exitConfig;
    final zone = zoneOf(config, s.err);
    if (zone == null) return exitConfig;

    final now = s.clock.now();
    if (argResults!.flag('scheduled') &&
        !scheduledBriefDue(config.brief, now: now, zone: zone)) {
      s.out.writeln(
        config.brief.enabled
            ? 'No brief due now (${describeBrief(config.brief)}).'
            : 'The morning brief is off.',
      );
      return 0;
    }

    final (events, tasks) = await _load(ctx, config, zone, now);
    final brief = BriefRenderer(clock: s.clock).render(
      config: config,
      events: events ?? const [],
      eventsLoaded: events != null,
      tasks: tasks ?? const [],
      zone: zone,
    );
    s.out.writeln(brief.text);
    if (!argResults!.flag('notify')) return 0;
    try {
      await s.notifier.notify(brief.title, brief.body);
    } on NotifyFailed catch (e) {
      s.err.writeln('Could not show the notification: ${e.message}.');
      return exitUnavailable;
    }
    return 0;
  }

  /// Today's events and the tasks; null for what could not be loaded.
  Future<(List<CalEvent>?, List<TaskItem>?)> _load(
    FolderContext ctx,
    AppConfig config,
    tz.Location zone,
    DateTime now,
  ) async {
    final g = globalResults!;
    final secrets = await findCalDavAccount(
      env: s.env,
      envFilePath: g.option('secrets-file') ?? defaultEnvFile(s.env),
      keyring: s.keyring,
      syncFolder: ctx.path,
    );
    secrets.warnings.forEach(s.err.writeln);
    final account = secrets.account;
    if (account == null) {
      s.err.writeln(
        'No CalDAV account: the brief has no events or tasks. Run '
        '`sasa status` for where it is looked up.',
      );
      return (null, null);
    }
    final source = s.sourceFor(account, zone);
    final day = TodayWindow.of(now, zone);
    Future<T?> attempt<T>(String what, Future<T> Function() load) async {
      try {
        return await load().timeout(sourceTimeout);
      } on TimeoutException {
        s.err.writeln('Could not load $what: the server did not answer.');
      } on Exception catch (e) {
        s.err.writeln('Could not load $what: $e');
      }
      return null;
    }

    return (
      await attempt('events', () => source.events(day.dayStart, day.dayEnd)),
      await attempt('tasks', source.tasks),
    );
  }
}
