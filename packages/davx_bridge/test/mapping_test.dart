import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sasa_core/sasa_core.dart';

import 'fake_bridge.dart';

void main() {
  final paris = locationFor('Europe/Paris');

  ProviderInstance inst({
    DateTime? begin,
    DateTime? end,
    int allDay = 0,
    int availability = 0,
    String? uid = 'uid-1',
    int? status = 1,
    String? location,
  }) => ProviderInstance.fromMap(
    instanceRow(
      begin: begin ?? DateTime.utc(2026, 11, 9, 8),
      end: end ?? DateTime.utc(2026, 11, 9, 9),
      allDay: allDay,
      availability: availability,
      uid: uid,
      status: status,
      location: location,
    ),
  );

  group('calEventOf', () {
    test('timed instance', () {
      final e = calEventOf(inst(location: ' Room 12 '))!;
      expect(e.uid, 'uid-1');
      expect(e.title, 'Event');
      expect(e.start, DateTime.utc(2026, 11, 9, 8));
      expect(e.end, DateTime.utc(2026, 11, 9, 9));
      expect(e.allDay, isFalse);
      expect(e.busy, isTrue);
      expect(e.calendarName, 'PhD');
      expect(e.location, 'Room 12');
      expect(e.description, isNull);
    });

    test('all-day instance keeps the UTC-midnight date', () {
      final e = calEventOf(
        inst(
          begin: DateTime.utc(2026, 11, 11),
          end: DateTime.utc(2026, 11, 12),
          allDay: 1,
        ),
      )!;
      expect(e.allDay, isTrue);
      expect(e.start, DateTime.utc(2026, 11, 11));
      expect(e.end, DateTime.utc(2026, 11, 12));
    });

    test('availability: free is not busy, tentative is', () {
      expect(
        calEventOf(inst(availability: ProviderInstance.availabilityFree))!.busy,
        isFalse,
      );
      expect(
        calEventOf(inst(availability: ProviderInstance.availabilityTentative))!
            .busy,
        isTrue,
      );
    });

    test('cancelled instances are dropped', () {
      expect(
        calEventOf(inst(status: ProviderInstance.statusCancelled)),
        isNull,
      );
    });

    test('events without UID get a stable device id', () {
      expect(calEventOf(inst(uid: null))!.uid, 'android-event-1');
    });
  });

  group('taskItemOf', () {
    ProviderTask task({
      int? due,
      int allDay = 0,
      int? priority,
      int? status = 0,
      int? completed,
      String? uid = 'task-1',
      String? title = ' Write intro ',
    }) => ProviderTask.fromMap(
      taskRow(
        due: due,
        allDay: allDay,
        priority: priority,
        status: status,
        completed: completed,
        uid: uid,
        title: title,
      ),
    );

    test('timed due is the stored instant', () {
      final t = taskItemOf(
        task(due: ms(DateTime.utc(2026, 11, 10, 16)), priority: 1),
        const ['writing'],
        paris,
      );
      expect(t.uid, 'task-1');
      expect(t.title, 'Write intro');
      expect(t.listName, 'PhD');
      expect(t.tags, ['writing']);
      expect(t.due, DateTime.utc(2026, 11, 10, 16));
      expect(t.priority, 1);
      expect(t.completed, isFalse);
    });

    test('date-only due is the end of that day in the zone', () {
      final t = taskItemOf(
        task(due: ms(DateTime.utc(2026, 11, 10)), allDay: 1),
        const [],
        paris,
      );
      expect(t.due, DateTime.utc(2026, 11, 10, 22, 59, 59));
    });

    test('no due date', () {
      expect(taskItemOf(task(), const [], paris).due, isNull);
    });

    test('priority 0 or out of range is undefined', () {
      expect(taskItemOf(task(priority: 0), const [], paris).priority, isNull);
      expect(taskItemOf(task(priority: 12), const [], paris).priority, isNull);
      expect(taskItemOf(task(priority: 9), const [], paris).priority, 9);
    });

    test('completed: status completed/cancelled or a completion time', () {
      bool done(ProviderTask t) => taskItemOf(t, const [], paris).completed;
      expect(done(task(status: ProviderTask.statusCompleted)), isTrue);
      expect(done(task(status: ProviderTask.statusCancelled)), isTrue);
      expect(done(task(status: ProviderTask.statusInProcess)), isFalse);
      expect(done(task(status: null, completed: 1)), isTrue);
    });

    test('missing UID and title', () {
      final t = taskItemOf(task(uid: null, title: null), const [], paris);
      expect(t.uid, 'android-task-1');
      expect(t.title, '');
    });
  });

  group('overlaps', () {
    final from = DateTime.utc(2026, 11, 9);
    final to = DateTime.utc(2026, 11, 10);
    CalEvent ev(DateTime s, DateTime e, {bool allDay = false}) => CalEvent(
      uid: 'u',
      title: 't',
      start: s,
      end: e,
      allDay: allDay,
      busy: true,
      calendarName: 'c',
    );

    test('half-open range', () {
      expect(
        overlaps(
          ev(DateTime.utc(2026, 11, 8, 23), DateTime.utc(2026, 11, 9)),
          from,
          to,
          paris,
        ),
        isFalse,
      );
      expect(
        overlaps(
          ev(DateTime.utc(2026, 11, 9, 23), DateTime.utc(2026, 11, 10, 1)),
          from,
          to,
          paris,
        ),
        isTrue,
      );
    });

    test('zero-length events count at their start', () {
      final at = DateTime.utc(2026, 11, 9);
      expect(overlaps(ev(at, at), from, to, paris), isTrue);
      expect(overlaps(ev(to, to), from, to, paris), isFalse);
    });

    test('all-day dates are read in the zone', () {
      // 10 Nov all day in Paris = 9 Nov 23:00Z → 10 Nov 23:00Z.
      final day = ev(
        DateTime.utc(2026, 11, 10),
        DateTime.utc(2026, 11, 11),
        allDay: true,
      );
      expect(overlaps(day, from, to, paris), isTrue);
      expect(
        overlaps(day, from, DateTime.utc(2026, 11, 9, 23), paris),
        isFalse,
      );
    });
  });
}
