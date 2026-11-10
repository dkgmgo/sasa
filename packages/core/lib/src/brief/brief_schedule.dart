import 'package:timezone/timezone.dart' as tz;

import '../time_zones.dart';
import 'brief_settings.dart';

/// How late a scheduled brief may still be sent, e.g. when the laptop wakes
/// up after the brief time. Later than this, it is skipped as stale.
const Duration briefLateLimit = Duration(hours: 3);

/// The brief time on the local date [y]-[m]-[d] in [zone].
///
/// A time that falls in a spring-forward gap moves forward by the gap,
/// like the alarm of a phone.
DateTime _briefOn(BriefSettings s, tz.Location zone, int y, int m, int d) =>
    utcInstant(tz.TZDateTime(zone, y, m, d, s.time.hour, s.time.minute));

/// The first brief strictly after [after], as a UTC instant; null when the
/// brief is off.
DateTime? nextBriefAt(
  BriefSettings settings, {
  required DateTime after,
  required tz.Location zone,
}) {
  if (!settings.enabled) return null;
  final l = tz.TZDateTime.from(after, zone);
  // A week and a day covers every pattern, whatever the starting weekday.
  for (var i = 0; i <= 7; i++) {
    final date = DateTime.utc(l.year, l.month, l.day + i);
    if (!settings.occursOn(date.weekday)) continue;
    final at = _briefOn(settings, zone, date.year, date.month, date.day);
    if (at.isAfter(after)) return at;
  }
  return null;
}

/// True when today's brief time (in [zone]) has passed by less than
/// [lateLimit] at [now]: a timer-started brief should be sent now.
bool scheduledBriefDue(
  BriefSettings settings, {
  required DateTime now,
  required tz.Location zone,
  Duration lateLimit = briefLateLimit,
}) {
  final l = tz.TZDateTime.from(now, zone);
  final date = DateTime.utc(l.year, l.month, l.day);
  if (!settings.occursOn(date.weekday)) return false;
  final at = _briefOn(settings, zone, date.year, date.month, date.day);
  return !now.isBefore(at) && now.isBefore(at.add(lateLimit));
}
