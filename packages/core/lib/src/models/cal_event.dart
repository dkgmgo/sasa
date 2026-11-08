import '../json.dart';
import '../time_zones.dart';

/// A calendar event instance (recurrences already expanded by the source).
///
/// Timed events: [start] and [end] are UTC instants.
///
/// All-day events ([allDay] true): [start] and [end] are calendar dates
/// stored as UTC midnight, with [end] exclusive (like iCalendar `DTEND`), so a
/// one-day event on 9 Nov has start 2026-11-09 and end 2026-11-10. They are
/// interpreted in the user's configured time zone.
final class CalEvent {
  CalEvent({
    required this.uid,
    required this.title,
    required DateTime start,
    required DateTime end,
    required this.allDay,
    required this.busy,
    required this.calendarName,
    this.location,
    this.description,
  }) : start = allDay ? _date(start) : utcInstant(start),
       end = allDay ? _date(end) : utcInstant(end);

  factory CalEvent.fromJson(Json json) => CalEvent(
    uid: json.req<String>('uid'),
    title: json.req<String>('title'),
    start: json.reqInstant('start'),
    end: json.reqInstant('end'),
    allDay: json.req<bool>('allDay'),
    busy: json.req<bool>('busy'),
    calendarName: json.req<String>('calendarName'),
    location: json.opt<String>('location'),
    description: json.opt<String>('description'),
  );

  static DateTime _date(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  final String uid;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  /// False for transparent events (`TRANSP:TRANSPARENT`), which never block
  /// time.
  final bool busy;
  final String calendarName;
  final String? location;
  final String? description;

  Json toJson() => {
    'uid': uid,
    'title': title,
    'start': instantToJson(start),
    'end': instantToJson(end),
    'allDay': allDay,
    'busy': busy,
    'calendarName': calendarName,
    if (location != null) 'location': location,
    if (description != null) 'description': description,
  };

  @override
  bool operator ==(Object other) =>
      other is CalEvent &&
      other.uid == uid &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.busy == busy &&
      other.calendarName == calendarName &&
      other.location == location &&
      other.description == description;

  @override
  int get hashCode => Object.hash(
    uid,
    title,
    start,
    end,
    allDay,
    busy,
    calendarName,
    location,
    description,
  );

  @override
  String toString() => 'CalEvent($uid, "$title", $start–$end)';
}
