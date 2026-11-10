import 'package:timezone/timezone.dart' as tz;

import '../clock.dart';
import '../config/app_config.dart';
import '../display.dart';
import '../greeting.dart';
import '../models/cal_event.dart';
import '../models/free_block.dart';
import '../models/nudge.dart';
import '../models/task_item.dart';
import '../time_zones.dart';
import '../today.dart';

/// Due tasks named in the brief; the rest are counted as "+N more".
const int briefMaxDueTasks = 3;

/// What to suggest for a free block (`Deep research block`), or null.
typedef BriefSuggestion = String? Function(FreeBlock block);

/// The rendered morning brief: a [title] line and body [lines].
final class Brief {
  Brief({required this.date, required this.title, required List<String> lines})
    : lines = List.unmodifiable(lines);

  /// The local date described, as UTC midnight.
  final DateTime date;

  /// `Sasa! Mon 9 Nov — 3 events · 5 h free`.
  final String title;
  final List<String> lines;

  /// The lines, one per row (a notification's body).
  String get body => lines.join('\n');

  /// Title and body, e.g. for a terminal.
  String get text => [title, ...lines].join('\n');

  @override
  String toString() => text;
}

/// Renders the morning brief from the day's events, tasks and nudges.
///
/// The brief describes the local day of the instant it is rendered for and
/// what is left of it from then on: what already ended is left out.
final class BriefRenderer {
  const BriefRenderer({required this.clock});

  final Clock clock;

  /// Renders the brief for the instant [at] (default: now), e.g. the next
  /// scheduled brief time, in [zone].
  ///
  /// [events] and [tasks] may cover more than that day. With [eventsLoaded]
  /// false, the brief says the calendar is unavailable instead of showing
  /// a falsely free day. [suggestFor] names an activity for a free block;
  /// nudges for which [nudgeSatisfied] is true are left out.
  Brief render({
    required AppConfig config,
    required Iterable<CalEvent> events,
    bool eventsLoaded = true,
    required Iterable<TaskItem> tasks,
    required tz.Location zone,
    DateTime? at,
    BriefSuggestion? suggestFor,
    bool Function(Nudge nudge)? nudgeSatisfied,
  }) {
    final now = utcInstant(at ?? clock.now());
    final view = buildToday(
      config: config,
      events: events,
      eventsLoaded: eventsLoaded,
      tasks: tasks,
      now: now,
      zone: zone,
    );
    final date = view.window.date;

    final lines = <String>[
      for (final e in view.allDay) 'All day  ${_eventLabel(e)}',
      if (!view.freeKnown) 'Could not load your calendar.',
    ];
    var eventCount = view.allDay.length;
    for (final entry in view.timeline) {
      if (entry.status == TimeStatus.past) continue;
      final range = formatTimeRange(entry.start, entry.end, zone);
      switch (entry) {
        case EventEntry():
          eventCount++;
          lines.add('$range  ${_eventLabel(entry)}');
        case FreeEntry(:final block):
          final free =
              '$range  free (${formatMinutes(block.length.inMinutes)})';
          final suggestion = suggestFor?.call(block);
          lines.add(
            suggestion == null ? free : '$free → suggested: $suggestion',
          );
      }
    }
    if (view.freeKnown && lines.isEmpty) lines.add('Nothing scheduled.');

    final footer = [
      if (_dueText(view.dueTasks, now, zone) case final due?) 'Due: $due',
      if (_nudgesText(config.nudges, date.weekday, nudgeSatisfied)
          case final nudges?)
        'Nudges: $nudges',
    ];
    if (footer.isNotEmpty) lines.add(footer.join(' · '));

    final String summary;
    if (!view.freeKnown) {
      summary = 'calendar unavailable';
    } else {
      final free = view.freeRemaining.inMinutes;
      final working = config.freeBlocks.workingHours
          .windowsFor(date.weekday)
          .isNotEmpty;
      summary = [
        switch (eventCount) {
          0 => 'no events',
          1 => '1 event',
          _ => '$eventCount events',
        },
        if (free > 0)
          '${formatMinutes(free)} free'
        else if (working)
          'no free time',
      ].join(' · ');
    }
    return Brief(
      date: date,
      title: '$sasaGreeting ${formatShortDate(date)} — $summary',
      lines: lines,
    );
  }
}

String _eventLabel(EventEntry e) => switch (e.category) {
  null => e.event.title,
  final c => '${e.event.title} (${c.name})',
};

/// `review (today), report (overdue) +2 more`; null when nothing is due.
///
/// Due today comes first, then overdue (most recent first: an old backlog
/// should not hide this week's work), then the coming days.
String? _dueText(List<DueTask> due, DateTime now, tz.Location zone) {
  if (due.isEmpty) return null;
  final today = _localDate(now, zone);
  int daysAhead(DueTask t) =>
      _localDate(t.task.due!, zone).difference(today).inDays;
  int rank(DueTask t) => t.overdue
      ? 1
      : daysAhead(t) == 0
      ? 0
      : 2;
  final sorted = [for (var i = 0; i < due.length; i++) (i, due[i])]
    ..sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      if (byRank != 0) return byRank;
      // Overdue: newest first; otherwise keep the soonest-first order.
      return a.$2.overdue ? b.$1.compareTo(a.$1) : a.$1.compareTo(b.$1);
    });

  String label(DueTask t) {
    if (t.overdue) return 'overdue';
    return switch (daysAhead(t)) {
      0 => 'today',
      1 => 'tomorrow',
      final n => 'in $n days',
    };
  }

  final shown = [
    for (final (_, t) in sorted.take(briefMaxDueTasks))
      '${t.task.title} (${label(t)})',
  ].join(', ');
  final more = due.length - briefMaxDueTasks;
  return more > 0 ? '$shown +$more more' : shown;
}

String? _nudgesText(
  List<Nudge> nudges,
  int weekday,
  bool Function(Nudge)? satisfied,
) {
  final open = [
    for (final n in nudges)
      if (n.schedule.weekdays.contains(weekday) &&
          !(satisfied?.call(n) ?? false))
        n.title,
  ];
  return open.isEmpty ? null : open.join(', ');
}

DateTime _localDate(DateTime instant, tz.Location zone) {
  final l = tz.TZDateTime.from(instant, zone);
  return DateTime.utc(l.year, l.month, l.day);
}
