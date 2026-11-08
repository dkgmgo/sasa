import '../json.dart';
import '../time_zones.dart';

/// A to-do item (VTODO), e.g. from Tasks.org.
final class TaskItem {
  TaskItem({
    required this.uid,
    required this.title,
    required this.listName,
    required List<String> tags,
    DateTime? due,
    this.priority,
    required this.completed,
  }) : tags = List.unmodifiable(tags),
       due = due == null ? null : utcInstant(due);

  factory TaskItem.fromJson(Json json) => TaskItem(
    uid: json.req<String>('uid'),
    title: json.req<String>('title'),
    listName: json.req<String>('listName'),
    tags: json.reqList('tags', (e) {
      if (e is String) return e;
      throw FormatException('Tag must be a string: $e');
    }),
    due: json.optInstant('due'),
    priority: json.opt<int>('priority'),
    completed: json.req<bool>('completed'),
  );

  final String uid;
  final String title;
  final String listName;
  final List<String> tags;
  final DateTime? due;

  /// iCalendar priority: 1 (highest) … 9 (lowest); null when undefined.
  final int? priority;
  final bool completed;

  Json toJson() => {
    'uid': uid,
    'title': title,
    'listName': listName,
    'tags': tags,
    if (due != null) 'due': instantToJson(due!),
    if (priority != null) 'priority': priority,
    'completed': completed,
  };

  @override
  bool operator ==(Object other) =>
      other is TaskItem &&
      other.uid == uid &&
      other.title == title &&
      other.listName == listName &&
      listEquals(other.tags, tags) &&
      other.due == due &&
      other.priority == priority &&
      other.completed == completed;

  @override
  int get hashCode => Object.hash(
    uid,
    title,
    listName,
    Object.hashAll(tags),
    due,
    priority,
    completed,
  );

  @override
  String toString() => 'TaskItem($uid, "$title", $listName)';
}
