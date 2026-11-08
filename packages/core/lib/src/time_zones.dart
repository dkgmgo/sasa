import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _initialised = false;

/// Returns the IANA [name] location (e.g. `Europe/Paris`), loading the
/// bundled time-zone database on first use.
///
/// Throws [tz.LocationNotFoundException] for an unknown name.
tz.Location locationFor(String name) {
  if (!_initialised) {
    tzdata.initializeTimeZones();
    _initialised = true;
  }
  return tz.getLocation(name);
}

/// Converts any [DateTime] (including a `TZDateTime`) to a plain UTC
/// [DateTime] for the same instant.
DateTime utcInstant(DateTime d) =>
    DateTime.fromMicrosecondsSinceEpoch(d.microsecondsSinceEpoch, isUtc: true);

/// The last second (23:59:59) of the calendar [date] in [zone], as a UTC
/// instant. Only the date fields of [date] are used.
///
/// Used for date-only task due dates, which count as due until the end of
/// that day.
DateTime endOfLocalDate(DateTime date, tz.Location zone) =>
    utcInstant(tz.TZDateTime(zone, date.year, date.month, date.day + 1))
        .subtract(const Duration(seconds: 1));
