/// Maps parsed iCalendar data to core's [CalEvent] and [TaskItem].
library;

import 'package:sasa_core/sasa_core.dart';

import 'expand.dart';
import 'ical_parser.dart';
import 'ical_values.dart';

/// Event instances overlapping `[from, to)` in one calendar object
/// resource (or any iCalendar text), sorted by start.
///
/// All-day instances are compared with the range in [zones]' default zone.
List<CalEvent> eventsFromIcal(
  String ics, {
  required String calendarName,
  required DateTime from,
  required DateTime to,
  required ZoneResolver zones,
}) {
  final vevents = [
    for (final cal in parseIcal(ics)) ...cal.childrenNamed('VEVENT'),
  ];
  final events = [
    for (final o in expandEvents(vevents, from: from, to: to, zones: zones))
      calEventOf(o, calendarName: calendarName),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return events;
}

/// [CalEvent] for one expanded occurrence.
CalEvent calEventOf(EventOccurrence o, {required String calendarName}) {
  final c = o.component;
  return CalEvent(
    uid: c.property('UID')?.value.trim() ?? '',
    title: _text(c, 'SUMMARY') ?? '',
    start: o.start,
    end: o.end,
    allDay: o.allDay,
    busy: c.property('TRANSP')?.value.trim().toUpperCase() != 'TRANSPARENT',
    calendarName: calendarName,
    location: _text(c, 'LOCATION'),
    description: _text(c, 'DESCRIPTION'),
  );
}

/// Tasks in one calendar object resource. Recurring VTODOs give their
/// master only; RECURRENCE-ID overrides are ignored.
List<TaskItem> tasksFromIcal(
  String ics, {
  required String listName,
  required ZoneResolver zones,
}) => [
  for (final cal in parseIcal(ics))
    for (final todo in cal.childrenNamed('VTODO'))
      if (todo.property('RECURRENCE-ID') == null)
        taskItemOf(todo, listName: listName, zones: zones),
];

/// [TaskItem] for one VTODO.
///
/// - `completed`: `STATUS:COMPLETED`/`CANCELLED` or a `COMPLETED` date.
/// - `due`: a date-only DUE means the end of that day (23:59:59) in the
///   default zone.
/// - `priority`: 1–9, or null when 0/absent/invalid.
TaskItem taskItemOf(
  IcalComponent todo, {
  required String listName,
  required ZoneResolver zones,
}) {
  final status = todo.property('STATUS')?.value.trim().toUpperCase();
  final completed =
      status == 'COMPLETED' ||
      status == 'CANCELLED' ||
      todo.property('COMPLETED') != null;
  final prio = int.tryParse(todo.property('PRIORITY')?.value.trim() ?? '');
  return TaskItem(
    uid: todo.property('UID')?.value.trim() ?? '',
    title: _text(todo, 'SUMMARY') ?? '',
    listName: listName,
    tags: [
      for (final p in todo.propertiesNamed('CATEGORIES'))
        for (final t in splitTextList(p.value))
          if (t.trim().isNotEmpty) t.trim(),
    ],
    due: _due(todo, zones),
    priority: prio != null && prio >= 1 && prio <= 9 ? prio : null,
    completed: completed,
  );
}

DateTime? _due(IcalComponent todo, ZoneResolver zones) {
  final IcalDateTime? due;
  try {
    due = dateTimeOf(todo.property('DUE'));
  } on FormatException {
    return null;
  }
  if (due == null) return null;
  if (!due.isDate) return due.instant(zones);
  return endOfLocalDate(due.wall, zones.defaultZone);
}

String? _text(IcalComponent c, String name) {
  final p = c.property(name);
  if (p == null) return null;
  final v = unescapeText(p.value).trim();
  return v.isEmpty ? null : v;
}
