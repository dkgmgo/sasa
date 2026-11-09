import 'package:timezone/timezone.dart' as tz;

import 'models/category.dart';
import 'models/energy.dart';
import 'models/mapping_rule.dart';

/// User-facing text shared by the app and the command-line tool. English
/// only for now.

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Local `HH:mm` of [instant] in [zone].
String formatClock(DateTime instant, tz.Location zone) {
  final l = tz.TZDateTime.from(instant, zone);
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// `09:00–10:30`.
String formatTimeRange(DateTime start, DateTime end, tz.Location zone) =>
    '${formatClock(start, zone)}–${formatClock(end, zone)}';

/// `45 min`, `1 h`, `1 h 30`.
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${_two(m)}';
}

/// `Monday 9 November`, from the date fields of [date].
String formatDate(DateTime date) =>
    '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';

/// `Mon 9 Nov`, from the date fields of [date].
String formatShortDate(DateTime date) =>
    '${_weekdays[date.weekday - 1].substring(0, 3)} ${date.day} '
    '${_months[date.month - 1].substring(0, 3)}';

/// When a task is due, relative to [now]: `Today 18:00`, `Tomorrow`,
/// `Wed 11 Nov`, prefixed `Overdue · ` when past. Date-only due dates (stored
/// as 23:59:59 local) show no time.
String formatDue(
  DateTime due, {
  required DateTime now,
  required tz.Location zone,
}) {
  final d = tz.TZDateTime.from(due, zone);
  final n = tz.TZDateTime.from(now, zone);
  final days = DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
  final day = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => formatShortDate(DateTime.utc(d.year, d.month, d.day)),
  };
  final dateOnly = d.hour == 23 && d.minute == 59;
  final text = dateOnly ? day : '$day ${formatClock(due, zone)}';
  return due.isBefore(now) ? 'Overdue · $text' : text;
}

/// What a rule matches, e.g. `Calendar is “Cours”`.
String describeMatch(MappingRule rule) => switch (rule.field) {
  MatchField.calendar => 'Calendar is “${rule.pattern}”',
  MatchField.list => 'List is “${rule.pattern}”',
  MatchField.tag => 'Tag is “${rule.pattern}”',
  MatchField.titleRegex => 'Title matches /${rule.pattern}/',
};

String matchFieldLabel(MatchField field) => switch (field) {
  MatchField.calendar => 'Calendar',
  MatchField.list => 'Task list',
  MatchField.tag => 'Task tag',
  MatchField.titleRegex => 'Title (regular expression)',
};

String energyLabel(Energy energy) => switch (energy) {
  Energy.low => 'Low',
  Energy.medium => 'Medium',
  Energy.high => 'High',
};

/// One-line summary of a category's settings:
/// `8 h a week · 45 min blocks · medium energy · best 09:00–12:00`.
String describeCategory(Category c) => [
  c.weeklyTargetMin == 0
      ? 'No weekly target'
      : '${formatMinutes(c.weeklyTargetMin)} a week',
  '${formatMinutes(c.defaultDurationMin)} blocks',
  '${energyLabel(c.defaultEnergy).toLowerCase()} energy',
  if (c.preferredWindow case final w?) 'best $w',
].join(' · ');
