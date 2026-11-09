import 'package:timezone/timezone.dart' as tz;

import 'categoriser.dart';
import 'config/app_config.dart';
import 'free_blocks.dart';
import 'models/cal_event.dart';
import 'models/category.dart';
import 'models/free_block.dart';
import 'models/task_item.dart';
import 'time_zones.dart';

/// Days of events loaded from today on, for the Unclassified inbox.
const int inboxLookaheadDays = 14;

/// Open tasks due before the start of the local day this many days ahead
/// count as "due soon" (3: today, tomorrow and the day after).
const int dueSoonDays = 3;

/// Overdue tasks shown before "show all": the most recent ones.
const int maxOverdueShown = 10;

/// The due tasks to show, and how many older overdue ones are hidden.
final class DueTaskSelection {
  DueTaskSelection(List<DueTask> tasks, this.hiddenOverdue)
    : tasks = List.unmodifiable(tasks);

  final List<DueTask> tasks;
  final int hiddenOverdue;
}

/// The local day containing an instant, and the range to load for it.
final class TodayWindow {
  TodayWindow._(this.date, this.dayStart, this.dayEnd, this.fetchEnd);

  factory TodayWindow.of(DateTime now, tz.Location zone) {
    final l = tz.TZDateTime.from(now, zone);
    DateTime at(int days) =>
        utcInstant(tz.TZDateTime(zone, l.year, l.month, l.day + days));
    return TodayWindow._(
      DateTime.utc(l.year, l.month, l.day),
      at(0),
      at(1),
      at(inboxLookaheadDays),
    );
  }

  /// The local date, as UTC midnight (like all-day event dates).
  final DateTime date;

  /// Local midnight starting the day, as a UTC instant.
  final DateTime dayStart;

  /// Next local midnight, as a UTC instant.
  final DateTime dayEnd;

  /// End of the range to load: events in `[dayStart, fetchEnd)`.
  final DateTime fetchEnd;
}

/// Where something sits relative to now.
enum TimeStatus { past, current, upcoming }

TimeStatus _status(DateTime start, DateTime end, DateTime now) =>
    !end.isAfter(now)
    ? TimeStatus.past
    : start.isAfter(now)
    ? TimeStatus.upcoming
    : TimeStatus.current;

/// One row of the Today timeline.
sealed class TimelineEntry {
  const TimelineEntry(this.start, this.end, this.status);
  final DateTime start;
  final DateTime end;
  final TimeStatus status;
}

/// A calendar event, with its category when a rule matched.
final class EventEntry extends TimelineEntry {
  EventEntry(this.event, this.classification, this.category, DateTime now)
    : super(event.start, event.end, _status(event.start, event.end, now));

  final CalEvent event;
  final Classification? classification;

  /// Null when the event is unclassified.
  final Category? category;
}

/// Free working time.
final class FreeEntry extends TimelineEntry {
  FreeEntry(this.block, DateTime now)
    : super(block.start, block.end, _status(block.start, block.end, now));

  final FreeBlock block;
}

/// An open task that is due soon.
final class DueTask {
  const DueTask(this.task, this.classification, this.category, this.overdue);

  final TaskItem task;
  final Classification? classification;

  /// Null when the task is unclassified.
  final Category? category;
  final bool overdue;
}

/// Everything the Today screen shows.
final class TodayView {
  TodayView({
    required this.window,
    required List<EventEntry> allDay,
    required List<TimelineEntry> timeline,
    required List<DueTask> dueTasks,
    required this.nowIndex,
    this.freeKnown = true,
  }) : allDay = List.unmodifiable(allDay),
       timeline = List.unmodifiable(timeline),
       dueTasks = List.unmodifiable(dueTasks);

  final TodayWindow window;

  /// All-day events covering today, in source order.
  final List<EventEntry> allDay;

  /// Timed events overlapping today and the free blocks left from now on,
  /// sorted by start (events first on a tie).
  final List<TimelineEntry> timeline;

  /// Open tasks due soon (see [dueSoonDays]), overdue ones first.
  final List<DueTask> dueTasks;

  /// Index of the first [timeline] entry that is not past: where a "now"
  /// marker goes. Equals the length when everything is past.
  final int nowIndex;

  /// False when the events could not be loaded: free time is then unknown
  /// and [timeline] has no free blocks.
  final bool freeKnown;

  /// [dueTasks], keeping only the [maxOverdueShown] most recent overdue
  /// ones unless [showAllOverdue]: a long backlog would bury today's tasks.
  DueTaskSelection visibleDueTasks({required bool showAllOverdue}) {
    final overdue = dueTasks.where((t) => t.overdue).length;
    final hidden = showAllOverdue || overdue <= maxOverdueShown
        ? 0
        : overdue - maxOverdueShown;
    // Overdue tasks come first, oldest first: skip the oldest.
    return DueTaskSelection(dueTasks.sublist(hidden), hidden);
  }

  Iterable<FreeBlock> get free =>
      timeline.whereType<FreeEntry>().map((e) => e.block);

  /// Free working time left today.
  Duration get freeRemaining =>
      free.fold(Duration.zero, (sum, b) => sum + b.length);
}

/// Builds the Today view for the local day of [now] in [zone].
///
/// [events] may cover more than today (e.g. the whole inbox range); only
/// those overlapping today are shown, but all of them are used to compute
/// free blocks, which start at [now] (free time already past is left out).
/// With [eventsLoaded] false (the source failed), no free blocks are
/// computed: an empty calendar would wrongly look like a free day.
TodayView buildToday({
  required AppConfig config,
  required Iterable<CalEvent> events,
  bool eventsLoaded = true,
  required Iterable<TaskItem> tasks,
  required DateTime now,
  required tz.Location zone,
}) {
  final window = TodayWindow.of(now, zone);
  final categoriser = Categoriser(
    rules: config.rules,
    categories: config.categories,
  );

  EventEntry entry(CalEvent e, DateTime at) {
    final c = categoriser.classifyEvent(e);
    return EventEntry(e, c, _category(config, c), at);
  }

  final allDay = <EventEntry>[];
  final timed = <EventEntry>[];
  for (final e in events) {
    if (e.allDay) {
      // All-day events hold local dates: compare them with today's date.
      if (!e.start.isAfter(window.date) && e.end.isAfter(window.date)) {
        allDay.add(entry(e, window.date));
      }
    } else if (e.start.isBefore(window.dayEnd) &&
        e.end.isAfter(window.dayStart)) {
      timed.add(entry(e, now));
    }
  }

  final from = now.isAfter(window.dayStart) ? now : window.dayStart;
  final free = !eventsLoaded
      ? const <FreeBlock>[]
      : computeFreeBlocks(
          from: from,
          to: window.dayEnd,
          events: events,
          settings: config.freeBlocks,
          location: zone,
        );

  final timeline = <TimelineEntry>[
    ...timed,
    for (final b in free) FreeEntry(b, now),
  ];
  // Events before free blocks on equal starts; sort is not stable, so the
  // original index breaks remaining ties.
  final indexed = [for (var i = 0; i < timeline.length; i++) (i, timeline[i])]
    ..sort((a, b) {
      final byStart = a.$2.start.compareTo(b.$2.start);
      if (byStart != 0) return byStart;
      final byKind = _kind(a.$2).compareTo(_kind(b.$2));
      return byKind != 0 ? byKind : a.$1.compareTo(b.$1);
    });
  final sorted = [for (final (_, e) in indexed) e];
  final nowIndex = sorted.indexWhere((e) => e.status != TimeStatus.past);

  final dueLimit = utcInstant(
    tz.TZDateTime(
      zone,
      window.date.year,
      window.date.month,
      window.date.day + dueSoonDays,
    ),
  );
  final due = <DueTask>[];
  for (final t in tasks) {
    if (t.completed || t.due == null || !t.due!.isBefore(dueLimit)) continue;
    final c = categoriser.classifyTask(t);
    due.add(DueTask(t, c, _category(config, c), t.due!.isBefore(now)));
  }
  due.sort(_byDueThenPriority);

  return TodayView(
    window: window,
    allDay: allDay,
    timeline: sorted,
    dueTasks: due,
    nowIndex: nowIndex < 0 ? sorted.length : nowIndex,
    freeKnown: eventsLoaded,
  );
}

int _kind(TimelineEntry e) => e is EventEntry ? 0 : 1;

Category? _category(AppConfig config, Classification? c) =>
    c == null ? null : config.categoryById(c.categoryId);

int _byDueThenPriority(DueTask a, DueTask b) {
  final byDue = a.task.due!.compareTo(b.task.due!);
  if (byDue != 0) return byDue;
  // iCalendar: 1 is highest, 9 lowest; undefined after all of them.
  final pa = a.task.priority ?? 10;
  final pb = b.task.priority ?? 10;
  final byPriority = pa.compareTo(pb);
  return byPriority != 0 ? byPriority : a.task.uid.compareTo(b.task.uid);
}
