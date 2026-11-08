import 'package:sasa_caldav/sasa_caldav.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

TaskItem task(String ics) =>
    tasksFromIcal(ics, listName: 'Tasks', zones: parisZones()).single;

void main() {
  test('seed: priority, due with TZID, several categories', () {
    final t = task(seed('tasks/review-paper.ics'));
    expect(t.uid, 'sasa-seed-review-paper');
    expect(t.title, 'Review paper for workshop X');
    expect(t.listName, 'Tasks');
    expect(t.tags, ['review', 'research']);
    expect(t.priority, 1);
    expect(t.due, p(2026, 11, 3, 18));
    expect(t.completed, isFalse);
  });

  test('seed: date-only DUE means the end of that day in the default zone', () {
    final t = task(seed('tasks/prepare-lab-sockets.ics'));
    expect(t.due, p(2026, 11, 9).subtract(const Duration(seconds: 1)));
    expect(t.priority, 5);
  });

  test('seed: no due date', () {
    final t = task(seed('tasks/read-openalex-docs.ics'));
    expect(t.due, isNull);
    expect(t.priority, isNull);
    expect(t.tags, ['reading']);
  });

  test('seed: completed task', () {
    expect(task(seed('tasks/expense-report-done.ics')).completed, isTrue);
  });

  test('CANCELLED or a COMPLETED date count as completed', () {
    expect(
      task(vcal('BEGIN:VTODO\nUID:a\nSTATUS:CANCELLED\nEND:VTODO')).completed,
      isTrue,
    );
    expect(
      task(vcal('BEGIN:VTODO\nUID:b\nCOMPLETED:20261101T100000Z\nEND:VTODO'))
          .completed,
      isTrue,
    );
    expect(
      task(vcal('BEGIN:VTODO\nUID:c\nSTATUS:IN-PROCESS\nEND:VTODO')).completed,
      isFalse,
    );
  });

  test('PRIORITY 0 or out of range is undefined', () {
    expect(
      task(vcal('BEGIN:VTODO\nUID:a\nPRIORITY:0\nEND:VTODO')).priority,
      isNull,
    );
    expect(
      task(vcal('BEGIN:VTODO\nUID:a\nPRIORITY:12\nEND:VTODO')).priority,
      isNull,
    );
  });

  test('CATEGORIES over several lines, escaped commas, blanks dropped', () {
    final t = task(
      vcal(r'''
      BEGIN:VTODO
      UID:a
      CATEGORIES:one,two
      CATEGORIES:a\,b,
      END:VTODO'''),
    );
    expect(t.tags, ['one', 'two', 'a,b']);
  });

  test('UTC DUE and invalid DUE', () {
    expect(
      task(vcal('BEGIN:VTODO\nUID:a\nDUE:20261103T170000Z\nEND:VTODO')).due,
      z(2026, 11, 3, 17),
    );
    expect(task(vcal('BEGIN:VTODO\nUID:a\nDUE:soon\nEND:VTODO')).due, isNull);
  });

  test('recurring VTODO: overrides are ignored, master kept', () {
    final tasks = tasksFromIcal(
      vcal('''
        BEGIN:VTODO
        UID:r
        SUMMARY:Weekly report
        RRULE:FREQ=WEEKLY
        DUE;TZID=Europe/Paris:20261106T170000
        END:VTODO
        BEGIN:VTODO
        UID:r
        RECURRENCE-ID;TZID=Europe/Paris:20261106T170000
        SUMMARY:Weekly report (this week)
        END:VTODO'''),
      listName: 'Tasks',
      zones: parisZones(),
    );
    expect([for (final t in tasks) t.title], ['Weekly report']);
  });
}
