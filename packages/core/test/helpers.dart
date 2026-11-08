import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

/// Europe/Paris, the zone every DST test runs in.
final tz.Location paris = locationFor('Europe/Paris');

/// UTC instant of a Paris wall-clock time.
DateTime p(int y, int m, int d, [int h = 0, int min = 0]) =>
    utcInstant(tz.TZDateTime(paris, y, m, d, h, min));

/// UTC instant.
DateTime z(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

CalEvent event(
  DateTime start,
  DateTime end, {
  String uid = 'e',
  String title = 'Event',
  bool busy = true,
  bool allDay = false,
  String calendarName = 'Personal',
}) => CalEvent(
  uid: uid,
  title: title,
  start: start,
  end: end,
  allDay: allDay,
  busy: busy,
  calendarName: calendarName,
);

/// All-day event covering local dates [first, lastExclusive).
CalEvent allDay(
  DateTime first,
  DateTime lastExclusive, {
  bool busy = true,
  String uid = 'a',
}) => CalEvent(
  uid: uid,
  title: 'All day',
  start: first,
  end: lastExclusive,
  allDay: true,
  busy: busy,
  calendarName: 'Personal',
);

TimeWindow w(String start, String end) =>
    TimeWindow(LocalTime.parse(start), LocalTime.parse(end));
