/// Expands VEVENTs (RRULE, RDATE, EXDATE, RECURRENCE-ID) into occurrences
/// overlapping a range.
library;

import 'package:rrule/rrule.dart';
import 'package:timezone/timezone.dart' as tz;

import 'ical_parser.dart';
import 'ical_values.dart';

/// One concrete occurrence of a VEVENT.
///
/// Timed: [start]/[end] are UTC instants. All-day: they are dates at UTC
/// midnight, [end] exclusive (the convention of core's `CalEvent`).
final class EventOccurrence {
  EventOccurrence({
    required this.component,
    required this.allDay,
    required this.start,
    required this.end,
  });

  /// The master VEVENT or the RECURRENCE-ID override it came from.
  final IcalComponent component;
  final bool allDay;
  final DateTime start;
  final DateTime end;

  @override
  String toString() =>
      'EventOccurrence(${component.property('UID')?.value}, $start–$end'
      '${allDay ? ' all-day' : ''})';
}

/// Safety cap on generated instances per series (e.g. `FREQ=MINUTELY`).
const int maxInstancesPerSeries = 50000;

/// Occurrences of [vevents] that overlap `[from, to)`, unsorted.
///
/// Components are grouped by UID; the one without RECURRENCE-ID is the
/// master. Cancelled events (`STATUS:CANCELLED`) are dropped. Floating
/// times, unknown TZIDs and all-day dates use [zones]' default zone.
List<EventOccurrence> expandEvents(
  Iterable<IcalComponent> vevents, {
  required DateTime from,
  required DateTime to,
  required ZoneResolver zones,
}) {
  final groups = <Object, List<IcalComponent>>{};
  for (final e in vevents) {
    final uid = e.property('UID')?.value;
    groups.putIfAbsent(uid ?? Object(), () => []).add(e);
  }
  final out = <EventOccurrence>[];
  for (final group in groups.values) {
    _expandGroup(group, from.toUtc(), to.toUtc(), zones, out);
  }
  return out;
}

void _expandGroup(
  List<IcalComponent> group,
  DateTime from,
  DateTime to,
  ZoneResolver zones,
  List<EventOccurrence> out,
) {
  IcalComponent? master;
  final overrides = <IcalComponent>[];
  for (final c in group) {
    if (c.property('RECURRENCE-ID') == null) {
      master ??= c;
    } else {
      overrides.add(c);
    }
  }

  final overriddenKeys = <int>{
    for (final o in overrides)
      _key(dateTimeOf(o.property('RECURRENCE-ID'))!, zones),
  };

  if (master != null && !_cancelled(master)) {
    final dtstart = dateTimeOf(master.property('DTSTART'));
    if (dtstart != null) {
      final span = _Span.of(master, dtstart, zones);
      final exdates = dateTimeListOf(master.propertiesNamed('EXDATE'));
      final exKeys = {for (final x in exdates) _key(x, zones)};
      final exDays = {
        for (final x in exdates)
          if (x.isDate) x.wall,
      };
      for (final start in _starts(master, dtstart, to, zones)) {
        final k = _key(start, zones);
        if (exKeys.contains(k) || overriddenKeys.contains(k)) continue;
        if (!start.isDate && exDays.contains(_dateOnly(start.wall))) continue;
        final occ = span.occurrence(master, start, zones);
        if (_overlaps(occ, from, to, zones)) out.add(occ);
      }
    }
  }

  for (final o in overrides) {
    if (_cancelled(o)) continue;
    final rid = dateTimeOf(o.property('RECURRENCE-ID'))!;
    final dtstart = dateTimeOf(o.property('DTSTART')) ?? rid;
    final occ = _Span.of(
      o,
      dtstart,
      zones,
      fallback: master,
    ).occurrence(o, dtstart, zones);
    if (_overlaps(occ, from, to, zones)) out.add(occ);
  }
}

bool _cancelled(IcalComponent c) =>
    c.property('STATUS')?.value.trim().toUpperCase() == 'CANCELLED';

DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Identity of an instance for EXDATE / RECURRENCE-ID matching.
int _key(IcalDateTime d, ZoneResolver zones) => d.isDate
    ? d.wall.microsecondsSinceEpoch
    : d.instant(zones).microsecondsSinceEpoch;

/// Start values of every instance up to [to] (plus a day of margin), in
/// the master's zone: DTSTART, RRULE instances and RDATEs, de-duplicated.
Iterable<IcalDateTime> _starts(
  IcalComponent master,
  IcalDateTime dtstart,
  DateTime to,
  ZoneResolver zones,
) {
  final zone = dtstart.isDate ? zones.defaultZone : dtstart.zone(zones);
  final seen = <int>{};
  final out = <IcalDateTime>[];
  void add(IcalDateTime d) {
    if (seen.add(_key(d, zones))) out.add(d);
  }

  add(dtstart);
  final limit = instantToWall(to, zone).add(const Duration(days: 1));
  final rrule = master.property('RRULE');
  if (rrule != null) {
    final rule = _parseRule(rrule.value, dtstart, zone);
    if (rule != null) {
      // RFC 5545: DTSTART is always the first instance and counts toward
      // COUNT, even when it does not match the rule.
      final count = rule.count;
      var n = 0;
      for (final wall in rule.getInstances(
        start: dtstart.wall,
        before: limit,
      )) {
        if (n == 0 && count != null && wall != dtstart.wall) n++;
        if (count != null && n >= count) break;
        if (++n > maxInstancesPerSeries) break;
        add(dtstart.withWall(wall));
      }
    }
  }
  for (final r in dateTimeListOf(master.propertiesNamed('RDATE'))) {
    if (r.isDate && dtstart.isDate) {
      add(r);
    } else if (!r.isDate && !dtstart.isDate) {
      // Re-express in the master's zone so durations follow its wall clock.
      add(dtstart.withWall(instantToWall(r.instant(zones), zone)));
    }
  }
  return out;
}

/// Parses [value] for `rrule`: drops WKST (only MO is supported there; it
/// rarely changes results) and moves UNTIL into [dtstart]'s wall time.
/// Returns null for rules `rrule` cannot read; the event then occurs once.
RecurrenceRule? _parseRule(
  String value,
  IcalDateTime dtstart,
  tz.Location zone,
) {
  DateTime? until;
  final parts = <String>[];
  for (final part in value.split(';')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final key = part.substring(0, eq).trim().toUpperCase();
    final v = part.substring(eq + 1).trim();
    if (key == 'WKST') continue;
    if (key == 'UNTIL') {
      try {
        until = _untilWall(parseIcalDateTime(v), dtstart, zone);
      } on FormatException {
        return null;
      }
      continue;
    }
    parts.add('$key=$v');
  }
  try {
    final rule = RecurrenceRule.fromString('RRULE:${parts.join(';')}');
    return until == null ? rule : rule.copyWith(until: until);
  } on FormatException {
    return null;
  }
}

DateTime _untilWall(
  IcalDateTime until,
  IcalDateTime dtstart,
  tz.Location zone,
) {
  if (until.isDate) {
    // A date UNTIL includes that whole day.
    return dtstart.isDate
        ? until.wall
        : until.wall.add(const Duration(hours: 23, minutes: 59, seconds: 59));
  }
  if (dtstart.isDate) return _dateOnly(until.wall);
  if (until.isUtc && !dtstart.isUtc) return instantToWall(until.wall, zone);
  return until.wall;
}

/// How long each instance lasts: from DTEND (exact), DURATION (nominal days
/// + exact time) or the RFC 5545 defaults.
final class _Span {
  _Span._({this.exact, this.nominal, this.dateDays});

  factory _Span.of(
    IcalComponent c,
    IcalDateTime dtstart,
    ZoneResolver zones, {
    IcalComponent? fallback,
  }) {
    final dtend = dateTimeOf(c.property('DTEND'));
    final durProp = c.property('DURATION');
    if (dtstart.isDate) {
      if (dtend != null) {
        final days = dtend.wall.difference(_dateOnly(dtstart.wall)).inDays;
        return _Span._(dateDays: days < 1 ? 1 : days);
      }
      if (durProp != null) {
        final d = _tryDuration(durProp.value);
        if (d != null) return _Span._(dateDays: d.days < 1 ? 1 : d.days);
      }
    } else {
      if (dtend != null) {
        final exact = dtend.instant(zones).difference(dtstart.instant(zones));
        return _Span._(exact: exact.isNegative ? Duration.zero : exact);
      }
      if (durProp != null) {
        final d = _tryDuration(durProp.value);
        if (d != null) return _Span._(nominal: d);
      }
    }
    if (fallback != null) {
      final fs = dateTimeOf(fallback.property('DTSTART'));
      if (fs != null && fs.isDate == dtstart.isDate) {
        return _Span.of(fallback, fs, zones);
      }
    }
    return dtstart.isDate
        ? _Span._(dateDays: 1)
        : _Span._(exact: Duration.zero);
  }

  final Duration? exact;
  final IcalDuration? nominal;
  final int? dateDays;

  static IcalDuration? _tryDuration(String v) {
    try {
      return parseIcalDuration(v);
    } on FormatException {
      return null;
    }
  }

  EventOccurrence occurrence(
    IcalComponent c,
    IcalDateTime start,
    ZoneResolver zones,
  ) {
    if (start.isDate) {
      final s = _dateOnly(start.wall);
      return EventOccurrence(
        component: c,
        allDay: true,
        start: s,
        end: DateTime.utc(s.year, s.month, s.day + (dateDays ?? 1)),
      );
    }
    final zone = start.zone(zones);
    final s = wallToInstant(start.wall, zone);
    DateTime e;
    final n = nominal;
    if (n != null) {
      final w = start.wall;
      final endWall = DateTime.utc(
        w.year,
        w.month,
        w.day + n.days,
        w.hour,
        w.minute,
        w.second,
      );
      e = wallToInstant(endWall, zone).add(n.time);
    } else {
      e = s.add(exact ?? Duration.zero);
    }
    if (e.isBefore(s)) e = s;
    return EventOccurrence(component: c, allDay: false, start: s, end: e);
  }
}

bool _overlaps(
  EventOccurrence o,
  DateTime from,
  DateTime to,
  ZoneResolver zones,
) {
  final s = o.allDay ? wallToInstant(o.start, zones.defaultZone) : o.start;
  final e = o.allDay ? wallToInstant(o.end, zones.defaultZone) : o.end;
  if (!s.isBefore(to)) return false;
  if (e == s) return !s.isBefore(from);
  return e.isAfter(from);
}
