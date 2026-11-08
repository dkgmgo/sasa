import '../json.dart';

/// A wall-clock time of day (`HH:mm`), without a date or time zone.
///
/// `24:00` is allowed so a window can end at midnight.
final class LocalTime implements Comparable<LocalTime> {
  const LocalTime(this.hour, this.minute)
    : assert(hour >= 0 && hour <= 24),
      assert(minute >= 0 && minute < 60),
      assert(hour < 24 || minute == 0);

  /// Parses strict `HH:mm`.
  factory LocalTime.parse(String s) {
    final m = _pattern.firstMatch(s);
    if (m == null) throw FormatException('Invalid time (want HH:mm): "$s"');
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 24 || min > 59 || (h == 24 && min != 0)) {
      throw FormatException('Time out of range: "$s"');
    }
    return LocalTime(h, min);
  }

  static final _pattern = RegExp(r'^(\d{2}):(\d{2})$');

  final int hour;
  final int minute;

  int get minutesSinceMidnight => hour * 60 + minute;

  @override
  int compareTo(LocalTime other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  @override
  bool operator ==(Object other) =>
      other is LocalTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// A same-day wall-clock window `[start, end)`, e.g. 09:00–12:00.
///
/// Windows never cross midnight; split such a window in two.
final class TimeWindow {
  TimeWindow(this.start, this.end) {
    if (end.compareTo(start) <= 0) {
      throw ArgumentError('TimeWindow end $end must be after start $start');
    }
  }

  factory TimeWindow.fromJson(Json json) {
    final start = LocalTime.parse(json.req<String>('start'));
    final end = LocalTime.parse(json.req<String>('end'));
    if (end.compareTo(start) <= 0) {
      throw FormatException('TimeWindow end $end must be after start $start');
    }
    return TimeWindow(start, end);
  }

  final LocalTime start;
  final LocalTime end;

  bool contains(LocalTime t) => t.compareTo(start) >= 0 && t.compareTo(end) < 0;

  Json toJson() => {'start': '$start', 'end': '$end'};

  @override
  bool operator ==(Object other) =>
      other is TimeWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start–$end';
}
