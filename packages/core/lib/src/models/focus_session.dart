import '../json.dart';
import '../time_zones.dart';

/// A timed work session started from a suggestion.
final class FocusSession {
  FocusSession({
    required this.id,
    required this.activityId,
    required this.categoryId,
    required DateTime start,
    required DateTime end,
    required this.completed,
    this.note,
  }) : start = utcInstant(start),
       end = utcInstant(end);

  factory FocusSession.fromJson(Json json) => FocusSession(
    id: json.req<String>('id'),
    activityId: json.req<String>('activityId'),
    categoryId: json.req<String>('categoryId'),
    start: json.reqInstant('start'),
    end: json.reqInstant('end'),
    completed: json.req<bool>('completed'),
    note: json.opt<String>('note'),
  );

  final String id;
  final String activityId;
  final String categoryId;
  final DateTime start;
  final DateTime end;

  /// False when the session was abandoned.
  final bool completed;
  final String? note;

  Duration get duration => end.difference(start);

  Json toJson() => {
    'id': id,
    'activityId': activityId,
    'categoryId': categoryId,
    'start': instantToJson(start),
    'end': instantToJson(end),
    'completed': completed,
    if (note != null) 'note': note,
  };

  @override
  bool operator ==(Object other) =>
      other is FocusSession &&
      other.id == id &&
      other.activityId == activityId &&
      other.categoryId == categoryId &&
      other.start == start &&
      other.end == end &&
      other.completed == completed &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(id, activityId, categoryId, start, end, completed, note);

  @override
  String toString() => 'FocusSession($id, $categoryId, $start–$end)';
}
