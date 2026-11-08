import 'package:timezone/timezone.dart' as tz;

import 'json.dart';
import 'models/cal_event.dart';
import 'models/free_block.dart';
import 'models/local_time.dart';
import 'time_zones.dart';

const _dayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// Local working windows per weekday (`DateTime.monday` … `DateTime.sunday`).
final class WorkingHours {
  WorkingHours(Map<int, List<TimeWindow>> days)
    : _days = Map<int, List<TimeWindow>>.unmodifiable({
        for (final e in days.entries)
          if (e.value.isNotEmpty)
            _checkDay(e.key): List<TimeWindow>.unmodifiable(e.value),
      });

  /// The same windows on every day of the week.
  factory WorkingHours.everyDay(List<TimeWindow> windows) => WorkingHours({
    for (var d = DateTime.monday; d <= DateTime.sunday; d++) d: windows,
  });

  /// The same windows Monday to Friday.
  factory WorkingHours.weekdays(List<TimeWindow> windows) => WorkingHours({
    for (var d = DateTime.monday; d <= DateTime.friday; d++) d: windows,
  });

  /// Keys are `mon` … `sun`; absent days have no working hours.
  factory WorkingHours.fromJson(Json json) {
    final days = <int, List<TimeWindow>>{};
    for (final key in json.keys) {
      final i = _dayKeys.indexOf(key);
      if (i < 0) throw FormatException('Unknown weekday key "$key"');
      days[i + 1] = json.reqList(key, (e) => TimeWindow.fromJson(asJson(e)));
    }
    return WorkingHours(days);
  }

  static int _checkDay(int d) {
    if (d < DateTime.monday || d > DateTime.sunday) {
      throw ArgumentError('Weekday must be 1 (Mon) … 7 (Sun): $d');
    }
    return d;
  }

  final Map<int, List<TimeWindow>> _days;

  List<TimeWindow> windowsFor(int weekday) => _days[weekday] ?? const [];

  Json toJson() => {
    for (var d = DateTime.monday; d <= DateTime.sunday; d++)
      if (_days[d] case final windows?)
        _dayKeys[d - 1]: [for (final w in windows) w.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is WorkingHours && mapOfListsEquals(other._days, _days);

  @override
  int get hashCode => Object.hashAllUnordered(
    _days.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))),
  );
}

/// Configuration for [computeFreeBlocks].
final class FreeBlockSettings {
  FreeBlockSettings({
    required this.workingHours,
    required this.bufferMin,
    required this.minBlockMin,
  }) {
    if (bufferMin < 0 || minBlockMin < 0) {
      throw ArgumentError('bufferMin and minBlockMin must be ≥ 0');
    }
  }

  /// Mon–Fri 08:00–19:00, 5-min buffer, 15-min minimum block.
  factory FreeBlockSettings.defaults() => FreeBlockSettings(
    workingHours: WorkingHours.weekdays([
      TimeWindow(const LocalTime(8, 0), const LocalTime(19, 0)),
    ]),
    bufferMin: 5,
    minBlockMin: 15,
  );

  factory FreeBlockSettings.fromJson(Json json) {
    final buffer = json.req<int>('bufferMin');
    final minBlock = json.req<int>('minBlockMin');
    if (buffer < 0 || minBlock < 0) {
      throw const FormatException('bufferMin and minBlockMin must be ≥ 0');
    }
    return FreeBlockSettings(
      workingHours: WorkingHours.fromJson(json.reqObject('workingHours')),
      bufferMin: buffer,
      minBlockMin: minBlock,
    );
  }

  final WorkingHours workingHours;

  /// Minutes kept clear before and after each busy timed event.
  final int bufferMin;

  /// Free stretches shorter than this are dropped.
  final int minBlockMin;

  Json toJson() => {
    'workingHours': workingHours.toJson(),
    'bufferMin': bufferMin,
    'minBlockMin': minBlockMin,
  };

  @override
  bool operator ==(Object other) =>
      other is FreeBlockSettings &&
      other.workingHours == workingHours &&
      other.bufferMin == bufferMin &&
      other.minBlockMin == minBlockMin;

  @override
  int get hashCode => Object.hash(workingHours, bufferMin, minBlockMin);
}

/// Free working time in `[from, to)`, sorted, as UTC instants.
List<FreeBlock> computeFreeBlocks({
  required DateTime from,
  required DateTime to,
  required Iterable<CalEvent> events,
  required FreeBlockSettings settings,
  required tz.Location location,
}) {
  final rangeStart = utcInstant(from);
  final rangeEnd = utcInstant(to);
  if (!rangeStart.isBefore(rangeEnd)) return const [];

  final work = _merge(_workingSpans(rangeStart, rangeEnd, settings, location));
  final busy = _merge(_busySpans(events, settings.bufferMin, location));
  final minLength = Duration(minutes: settings.minBlockMin);

  final result = <FreeBlock>[];
  for (final span in _subtract(work, busy)) {
    final s = span.start.isBefore(rangeStart) ? rangeStart : span.start;
    final e = span.end.isAfter(rangeEnd) ? rangeEnd : span.end;
    if (!s.isBefore(e)) continue;
    if (e.difference(s) < minLength) continue;
    result.add(FreeBlock(start: s, end: e));
  }
  return List.unmodifiable(result);
}

final class _Span {
  _Span(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

DateTime _local(tz.Location loc, int y, int m, int d, [LocalTime? t]) =>
    utcInstant(tz.TZDateTime(loc, y, m, d, t?.hour ?? 0, t?.minute ?? 0));

Iterable<_Span> _workingSpans(
  DateTime from,
  DateTime to,
  FreeBlockSettings settings,
  tz.Location loc,
) sync* {
  final first = tz.TZDateTime.from(from, loc);
  var (y, m, d) = (first.year, first.month, first.day);
  while (true) {
    final dayStart = tz.TZDateTime(loc, y, m, d);
    if (!dayStart.isBefore(to)) return;
    for (final w in settings.workingHours.windowsFor(dayStart.weekday)) {
      yield _Span(_local(loc, y, m, d, w.start), _local(loc, y, m, d, w.end));
    }
    // Calendar arithmetic, not +24 h, so DST days keep their real length.
    final next = tz.TZDateTime(loc, y, m, d + 1);
    (y, m, d) = (next.year, next.month, next.day);
  }
}

Iterable<_Span> _busySpans(
  Iterable<CalEvent> events,
  int bufferMin,
  tz.Location loc,
) sync* {
  final buffer = Duration(minutes: bufferMin);
  for (final e in events) {
    if (!e.busy) continue;
    if (e.allDay) {
      final s = e.start;
      final x = e.end;
      yield _Span(
        _local(loc, s.year, s.month, s.day),
        _local(loc, x.year, x.month, x.day),
      );
    } else {
      yield _Span(e.start.subtract(buffer), e.end.add(buffer));
    }
  }
}

/// Sorts and unions spans; touching spans merge.
List<_Span> _merge(Iterable<_Span> spans) {
  final sorted = [
    for (final s in spans)
      if (s.start.isBefore(s.end)) s,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final out = <_Span>[];
  for (final s in sorted) {
    if (out.isNotEmpty && !s.start.isAfter(out.last.end)) {
      if (s.end.isAfter(out.last.end)) out.last = _Span(out.last.start, s.end);
    } else {
      out.add(s);
    }
  }
  return out;
}

/// [base] minus [holes]; both sorted and merged.
List<_Span> _subtract(List<_Span> base, List<_Span> holes) {
  final out = <_Span>[];
  var h = 0;
  for (final span in base) {
    var cursor = span.start;
    while (h < holes.length && !holes[h].end.isAfter(cursor)) {
      h++;
    }
    var i = h;
    while (i < holes.length && holes[i].start.isBefore(span.end)) {
      if (holes[i].start.isAfter(cursor)) {
        out.add(_Span(cursor, holes[i].start));
      }
      if (holes[i].end.isAfter(cursor)) cursor = holes[i].end;
      i++;
    }
    if (cursor.isBefore(span.end)) out.add(_Span(cursor, span.end));
  }
  return out;
}
