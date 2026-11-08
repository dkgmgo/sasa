import '../json.dart';
import 'local_time.dart';

/// Period over which a nudge's satisfaction is measured.
enum SchedulePeriod {
  /// The current local day.
  day,

  /// The current ISO week (Monday–Sunday).
  week,
}

/// On which weekdays a nudge is active and over which period it is judged.
///
/// "Weekdays, satisfied by ≥30 min today" is `{1..5}` + [SchedulePeriod.day];
/// "Sundays, satisfied by ≥45 min this week" is `{7}` + [SchedulePeriod.week].
final class Schedule {
  Schedule({required Set<int> weekdays, required this.period})
    : weekdays = Set.unmodifiable(weekdays) {
    for (final d in weekdays) {
      if (d < DateTime.monday || d > DateTime.sunday) {
        throw ArgumentError('Weekday must be 1 (Mon) … 7 (Sun): $d');
      }
    }
  }

  factory Schedule.fromJson(Json json) {
    final days = json.reqList('weekdays', (e) {
      if (e is int && e >= DateTime.monday && e <= DateTime.sunday) return e;
      throw FormatException('Weekday must be 1 (Mon) … 7 (Sun): $e');
    });
    return Schedule(
      weekdays: days.toSet(),
      period: json.reqEnum('period', SchedulePeriod.values),
    );
  }

  /// `DateTime.monday` (1) … `DateTime.sunday` (7).
  final Set<int> weekdays;
  final SchedulePeriod period;

  Json toJson() => {
    'weekdays': weekdays.toList()..sort(),
    'period': period.name,
  };

  @override
  bool operator ==(Object other) =>
      other is Schedule &&
      other.period == period &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);

  @override
  int get hashCode => Object.hash(period, Object.hashAllUnordered(weekdays));
}

/// A recurring, non-nagging reminder ("Read a paper").
final class Nudge {
  const Nudge({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.schedule,
    required this.window,
    required this.minMinutes,
    required this.durationMin,
  });

  factory Nudge.fromJson(Json json) => Nudge(
    id: json.req<String>('id'),
    title: json.req<String>('title'),
    categoryId: json.req<String>('categoryId'),
    schedule: Schedule.fromJson(json.reqObject('schedule')),
    window: TimeWindow.fromJson(json.reqObject('window')),
    minMinutes: json.req<int>('minMinutes'),
    durationMin: json.req<int>('durationMin'),
  );

  final String id;
  final String title;
  final String categoryId;
  final Schedule schedule;

  /// Local window in which the nudge may fire.
  final TimeWindow window;

  /// Minutes of [categoryId] in the schedule period that satisfy the nudge.
  final int minMinutes;

  /// Suggested session length when offered as a candidate.
  final int durationMin;

  Json toJson() => {
    'id': id,
    'title': title,
    'categoryId': categoryId,
    'schedule': schedule.toJson(),
    'window': window.toJson(),
    'minMinutes': minMinutes,
    'durationMin': durationMin,
  };

  @override
  bool operator ==(Object other) =>
      other is Nudge &&
      other.id == id &&
      other.title == title &&
      other.categoryId == categoryId &&
      other.schedule == schedule &&
      other.window == window &&
      other.minMinutes == minMinutes &&
      other.durationMin == durationMin;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    categoryId,
    schedule,
    window,
    minMinutes,
    durationMin,
  );

  @override
  String toString() => 'Nudge($id)';
}
