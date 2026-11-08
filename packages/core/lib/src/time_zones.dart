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
