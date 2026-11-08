import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final morning = event(z(2026, 11, 9, 8), z(2026, 11, 9, 9), uid: 'm');
  final noon = event(z(2026, 11, 9, 12), z(2026, 11, 9, 13), uid: 'n');
  final task = TaskItem(
    uid: 't',
    title: 'Task',
    listName: 'PhD',
    tags: const [],
    completed: false,
  );

  test('returns events overlapping the half-open range, sorted', () async {
    final CalendarSource source = FakeSource(
      events: [noon, morning],
      tasks: [task],
    );
    expect(await source.events(z(2026, 11, 9), z(2026, 11, 10)), [
      morning,
      noon,
    ]);
    // Ends exactly at range start: excluded. Starts at range end: excluded.
    expect(await source.events(z(2026, 11, 9, 9), z(2026, 11, 9, 12)), isEmpty);
    expect(await source.events(z(2026, 11, 9, 8, 30), z(2026, 11, 9, 8, 45)), [
      morning,
    ]);
    expect(await source.tasks(), [task]);
  });

  test('can be mutated between calls', () async {
    final source = FakeSource();
    expect(await source.tasks(), isEmpty);
    source.eventList.add(morning);
    expect(await source.events(z(2026, 11, 9), z(2026, 11, 10)), [morning]);
  });
}
