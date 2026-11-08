/// Typed reads of iCalendar DATE, DATE-TIME and DURATION values.
library;

import 'package:sasa_core/sasa_core.dart' show locationFor, utcInstant;
import 'package:timezone/timezone.dart' as tz;

import 'ical_parser.dart';

/// Maps `TZID` parameters to IANA locations.
///
/// Accepts plain IANA names and prefixed ones such as
/// `/freeassociation.sourceforge.net/Tzfile/Europe/Paris` (the trailing
/// `Area/City` is used). Floating times and unknown TZIDs fall back to
/// [defaultZone]. Custom `VTIMEZONE` rules are not interpreted.
final class ZoneResolver {
  ZoneResolver(this.defaultZone);

  /// Convenience constructor taking an IANA name.
  factory ZoneResolver.named(String name) => ZoneResolver(locationFor(name));

  final tz.Location defaultZone;
  final Map<String, tz.Location> _cache = {};

  /// Location for [tzid], or [defaultZone] when null or unknown.
  tz.Location resolve(String? tzid) {
    if (tzid == null || tzid.isEmpty) return defaultZone;
    return _cache.putIfAbsent(tzid, () => _lookup(tzid) ?? defaultZone);
  }

  static tz.Location? _lookup(String tzid) {
    final id = tzid.trim();
    if (id.toUpperCase() == 'UTC' || id.toUpperCase() == 'Z') {
      return tz.UTC;
    }
    final parts = id.split('/').where((s) => s.isNotEmpty).toList();
    // Try the longest suffix first: "a/America/Argentina/Salta" → ...
    for (var i = 0; i < parts.length; i++) {
      final candidate = parts.sublist(i).join('/');
      try {
        return locationFor(candidate);
      } on tz.LocationNotFoundException {
        continue;
      }
    }
    return null;
  }
}

/// A DATE or DATE-TIME value before time-zone resolution.
///
/// [wall] holds the written fields in a UTC-flagged [DateTime] (the
/// convention used by the `rrule` package for floating times).
final class IcalDateTime {
  IcalDateTime({
    required this.wall,
    required this.isDate,
    required this.isUtc,
    this.tzid,
  });

  final DateTime wall;

  /// `VALUE=DATE` (all-day).
  final bool isDate;

  /// Written with a trailing `Z`.
  final bool isUtc;

  /// `TZID` parameter, if any (ignored when [isUtc]).
  final String? tzid;

  /// Zone used to read [wall]: UTC, the TZID, or the default.
  tz.Location zone(ZoneResolver zones) => isUtc ? tz.UTC : zones.resolve(tzid);

  /// UTC instant of this value. A DATE maps to local midnight in [zones]'
  /// default zone.
  DateTime instant(ZoneResolver zones) => isDate
      ? wallToInstant(wall, zones.defaultZone)
      : wallToInstant(wall, zone(zones));

  /// Copy with other wall fields but the same zone information.
  IcalDateTime withWall(DateTime newWall) =>
      IcalDateTime(wall: newWall, isDate: isDate, isUtc: isUtc, tzid: tzid);

  @override
  String toString() =>
      'IcalDateTime($wall${isDate ? ' date' : ''}'
      '${isUtc ? ' Z' : ''}${tzid == null ? '' : ' $tzid'})';
}

/// Converts wall-clock fields (UTC-flagged) to the UTC instant in [zone].
/// Times inside a DST gap move forward, like most calendar apps.
DateTime wallToInstant(DateTime wall, tz.Location zone) => utcInstant(
  tz.TZDateTime(
    zone,
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  ),
);

/// Wall-clock fields (UTC-flagged) of [instant] in [zone].
DateTime instantToWall(DateTime instant, tz.Location zone) {
  final t = tz.TZDateTime.from(instant, zone);
  return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);
}

final _dateRe = RegExp(r'^(\d{4})(\d{2})(\d{2})$');
final _dateTimeRe = RegExp(
  r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$',
);

/// Parses one DATE or DATE-TIME [text], using [tzid] and [forceDate]
/// (`VALUE=DATE`) from the property parameters.
IcalDateTime parseIcalDateTime(
  String text, {
  String? tzid,
  bool forceDate = false,
}) {
  final s = text.trim().toUpperCase();
  final d = _dateRe.firstMatch(s);
  if (d != null) {
    return IcalDateTime(
      wall: DateTime.utc(_i(d, 1), _i(d, 2), _i(d, 3)),
      isDate: true,
      isUtc: false,
    );
  }
  final m = _dateTimeRe.firstMatch(s);
  if (m == null) throw FormatException('Invalid DATE-TIME: "$text"');
  final wall = DateTime.utc(
    _i(m, 1),
    _i(m, 2),
    _i(m, 3),
    _i(m, 4),
    _i(m, 5),
    _i(m, 6) == 60 ? 59 : _i(m, 6), // leap second
  );
  if (forceDate) {
    return IcalDateTime(
      wall: DateTime.utc(wall.year, wall.month, wall.day),
      isDate: true,
      isUtc: false,
    );
  }
  final utc = m.group(7) == 'Z';
  return IcalDateTime(
    wall: wall,
    isDate: false,
    isUtc: utc,
    tzid: utc ? null : tzid,
  );
}

int _i(RegExpMatch m, int g) => int.parse(m.group(g)!);

/// Reads a single date/date-time property (DTSTART, DTEND, DUE, …).
IcalDateTime? dateTimeOf(IcalProperty? p) {
  if (p == null) return null;
  return parseIcalDateTime(
    p.value,
    tzid: p.param('TZID'),
    forceDate: p.param('VALUE')?.toUpperCase() == 'DATE',
  );
}

/// Reads every value of a multi-valued date property (EXDATE, RDATE).
/// RDATE `PERIOD` values keep only their start.
List<IcalDateTime> dateTimeListOf(Iterable<IcalProperty> props) => [
  for (final p in props)
    for (final v in p.value.split(','))
      if (v.trim().isNotEmpty)
        parseIcalDateTime(
          v.split('/').first,
          tzid: p.param('TZID'),
          forceDate: p.param('VALUE')?.toUpperCase() == 'DATE',
        ),
];

/// An RFC 5545 DURATION: nominal [days] (weeks included, which follow
/// wall-clock days across DST) plus an exact [time] part.
final class IcalDuration {
  const IcalDuration({this.days = 0, this.time = Duration.zero});

  final int days;
  final Duration time;

  /// Approximate length, treating days as 24 h.
  Duration get approximate => Duration(days: days) + time;

  @override
  bool operator ==(Object other) =>
      other is IcalDuration && other.days == days && other.time == time;

  @override
  int get hashCode => Object.hash(days, time);

  @override
  String toString() => 'IcalDuration(${days}d, $time)';
}

final _durRe = RegExp(
  r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
);

/// Parses a DURATION such as `PT1H30M`, `P1D` or `-P2W`.
IcalDuration parseIcalDuration(String text) {
  final s = text.trim().toUpperCase();
  final m = _durRe.firstMatch(s);
  if (m == null || s == 'P' || s.endsWith('T')) {
    throw FormatException('Invalid DURATION: "$text"');
  }
  int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  final sign = m.group(1) == '-' ? -1 : 1;
  return IcalDuration(
    days: sign * (g(2) * 7 + g(3)),
    time: Duration(hours: g(4), minutes: g(5), seconds: g(6)) * sign,
  );
}
