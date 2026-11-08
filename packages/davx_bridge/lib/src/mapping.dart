// Pure Dart: provider rows to core models.

import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'provider_rows.dart';

/// [CalEvent] for one provider instance, or null for a cancelled one.
///
/// - `busy`: false only for "free" availability (tentative blocks time).
/// - `uid`: the iCalendar UID, or `android-event-<id>` before first sync.
/// - All-day instances are stored at UTC midnight, matching [CalEvent]'s
///   all-day convention.
CalEvent? calEventOf(ProviderInstance i) {
  if (i.status == ProviderInstance.statusCancelled) return null;
  return CalEvent(
    uid: i.uid ?? 'android-event-${i.eventId}',
    title: i.title?.trim() ?? '',
    start: DateTime.fromMillisecondsSinceEpoch(i.beginMs, isUtc: true),
    end: DateTime.fromMillisecondsSinceEpoch(i.endMs, isUtc: true),
    allDay: i.allDay,
    busy: i.availability != ProviderInstance.availabilityFree,
    calendarName: i.calendarName,
    location: i.location?.trim(),
    description: i.description?.trim(),
  );
}

/// [TaskItem] for one provider task, with the same rules as the CalDAV path:
///
/// - `completed`: status completed/cancelled, or a completion time.
/// - `due`: a date-only due means the end of that day (23:59:59) in [zone].
/// - `priority`: 1–9, or null when 0/absent/invalid.
/// - `uid`: the iCalendar UID, or `android-task-<id>` before first sync.
TaskItem taskItemOf(ProviderTask t, List<String> tags, tz.Location zone) {
  final due = t.dueMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(t.dueMs!, isUtc: true);
  final prio = t.priority;
  return TaskItem(
    uid: t.uid ?? 'android-task-${t.id}',
    title: t.title?.trim() ?? '',
    listName: t.listName,
    tags: tags,
    due: due == null || !t.dueAllDay ? due : endOfLocalDate(due, zone),
    priority: prio != null && prio >= 1 && prio <= 9 ? prio : null,
    completed:
        t.status == ProviderTask.statusCompleted ||
        t.status == ProviderTask.statusCancelled ||
        t.completedMs != null,
  );
}

/// Whether [e] overlaps `[from, to)`. All-day dates are read in [zone].
bool overlaps(CalEvent e, DateTime from, DateTime to, tz.Location zone) {
  final s = e.allDay ? _midnight(e.start, zone) : e.start;
  final en = e.allDay ? _midnight(e.end, zone) : e.end;
  if (s == en) return !s.isBefore(from) && s.isBefore(to);
  return s.isBefore(to) && en.isAfter(from);
}

DateTime _midnight(DateTime date, tz.Location zone) =>
    utcInstant(tz.TZDateTime(zone, date.year, date.month, date.day));
