import '../models/cal_event.dart';
import '../models/task_item.dart';

/// Read-only access to the user's calendars and task lists.
///
/// Implementations: the Android provider bridge, a CalDAV client, and
/// [FakeSource] for tests. Sources never write back.
abstract interface class CalendarSource {
  /// Event instances overlapping `[from, to)`, with recurrences expanded,
  /// sorted by start.
  Future<List<CalEvent>> events(DateTime from, DateTime to);

  /// All tasks, completed ones included.
  Future<List<TaskItem>> tasks();
}

/// In-memory [CalendarSource] for tests and demos.
///
/// Range filtering compares stored values directly, so all-day events (dates
/// at UTC midnight) are matched approximately; good enough for a fake.
final class FakeSource implements CalendarSource {
  FakeSource({List<CalEvent>? events, List<TaskItem>? tasks})
    : eventList = [...?events],
      taskList = [...?tasks];

  /// Mutable backing list of events.
  final List<CalEvent> eventList;

  /// Mutable backing list of tasks.
  final List<TaskItem> taskList;

  @override
  Future<List<CalEvent>> events(DateTime from, DateTime to) async {
    final hits = [
      for (final e in eventList)
        if (e.start.isBefore(to) && e.end.isAfter(from)) e,
    ]..sort((a, b) => a.start.compareTo(b.start));
    return List.unmodifiable(hits);
  }

  @override
  Future<List<TaskItem>> tasks() async => List.unmodifiable(taskList);
}
