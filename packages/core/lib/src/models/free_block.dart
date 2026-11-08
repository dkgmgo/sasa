import '../json.dart';
import '../time_zones.dart';

/// A stretch of free working time `[start, end)` between UTC instants.
final class FreeBlock {
  FreeBlock({required DateTime start, required DateTime end})
    : start = utcInstant(start),
      end = utcInstant(end) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('FreeBlock end $end is before start $start');
    }
  }

  factory FreeBlock.fromJson(Json json) =>
      FreeBlock(start: json.reqInstant('start'), end: json.reqInstant('end'));

  final DateTime start;
  final DateTime end;

  Duration get length => end.difference(start);

  Json toJson() => {'start': instantToJson(start), 'end': instantToJson(end)};

  @override
  bool operator ==(Object other) =>
      other is FreeBlock && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'FreeBlock($start–$end)';
}
