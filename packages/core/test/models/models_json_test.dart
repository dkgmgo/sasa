import 'dart:convert';

import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

/// Encodes to a JSON string and back, as the synced folder would.
T roundTrip<T>(Map<String, Object?> json, T Function(Map<String, Object?>) f) =>
    f(jsonDecode(jsonEncode(json)) as Map<String, Object?>);

void main() {
  group('CalEvent', () {
    final e = CalEvent(
      uid: 'u1',
      title: 'Lab Networks',
      start: DateTime.parse('2026-11-09T10:30:00+01:00'),
      end: DateTime.utc(2026, 11, 9, 11, 30),
      allDay: false,
      busy: true,
      calendarName: 'Cours',
      location: 'B204',
      description: 'Sockets',
    );

    test('normalises instants to UTC', () {
      expect(e.start, DateTime.utc(2026, 11, 9, 9, 30));
      expect(e.start.isUtc, isTrue);
    });

    test('round-trips JSON', () {
      expect(roundTrip(e.toJson(), CalEvent.fromJson), e);
      expect(e.toJson()['start'], '2026-11-09T09:30:00.000Z');
    });

    test('optional fields may be absent', () {
      final json = e.toJson()
        ..remove('location')
        ..remove('description');
      final parsed = CalEvent.fromJson(json);
      expect(parsed.location, isNull);
      expect(parsed.description, isNull);
    });

    test('all-day events keep their calendar date as UTC midnight', () {
      final a = CalEvent(
        uid: 'a',
        title: 'Conference',
        start: DateTime(2026, 11, 9, 15),
        end: DateTime(2026, 11, 11),
        allDay: true,
        busy: true,
        calendarName: 'Personal',
      );
      expect(a.start, DateTime.utc(2026, 11, 9));
      expect(a.end, DateTime.utc(2026, 11, 11));
      expect(roundTrip(a.toJson(), CalEvent.fromJson), a);
    });

    test('rejects timestamps without an offset', () {
      final json = e.toJson()..['start'] = '2026-11-09T10:30:00';
      expect(() => CalEvent.fromJson(json), throwsFormatException);
    });

    test('rejects wrong types', () {
      final json = e.toJson()..['busy'] = 'yes';
      expect(() => CalEvent.fromJson(json), throwsFormatException);
      expect(
        () => CalEvent.fromJson(e.toJson()..remove('uid')),
        throwsFormatException,
      );
    });

    test('value equality', () {
      expect(CalEvent.fromJson(e.toJson()).hashCode, e.hashCode);
      expect(CalEvent.fromJson(e.toJson()..['title'] = 'x'), isNot(e));
    });
  });

  group('TaskItem', () {
    final t = TaskItem(
      uid: 't1',
      title: 'Review paper',
      listName: 'PhD',
      tags: const ['review', 'urgent'],
      due: DateTime.utc(2026, 11, 12, 17),
      priority: 1,
      completed: false,
    );

    test('round-trips JSON', () {
      expect(roundTrip(t.toJson(), TaskItem.fromJson), t);
    });

    test('nullable fields', () {
      final bare = TaskItem(
        uid: 't2',
        title: 'x',
        listName: 'L',
        tags: const [],
        completed: true,
      );
      expect(roundTrip(bare.toJson(), TaskItem.fromJson), bare);
      expect(bare.due, isNull);
      expect(bare.priority, isNull);
    });

    test('tags are unmodifiable', () {
      final tags = ['a'];
      final task = TaskItem(
        uid: 'x',
        title: 'x',
        listName: 'x',
        tags: tags,
        completed: false,
      );
      tags.add('b');
      expect(task.tags, ['a']);
      expect(() => task.tags.add('c'), throwsUnsupportedError);
    });
  });

  group('Category', () {
    final c = Category(
      id: 'research',
      name: 'Research',
      color: '#3366CC',
      weeklyTargetMin: 900,
      defaultEnergy: Energy.high,
      defaultDurationMin: 90,
      preferredWindow: TimeWindow(
        const LocalTime(9, 0),
        const LocalTime(12, 0),
      ),
    );

    test('round-trips JSON with and without a preferred window', () {
      expect(roundTrip(c.toJson(), Category.fromJson), c);
      final noWindow = c.copyWith(clearPreferredWindow: true);
      expect(noWindow.preferredWindow, isNull);
      expect(roundTrip(noWindow.toJson(), Category.fromJson), noWindow);
    });

    test('rejects unknown energy', () {
      final json = c.toJson()..['defaultEnergy'] = 'turbo';
      expect(() => Category.fromJson(json), throwsFormatException);
    });
  });

  group('MappingRule', () {
    test('round-trips JSON', () {
      const rule = MappingRule(
        field: MatchField.titleRegex,
        pattern: r'^Lab\b',
        categoryId: 'teaching',
        priority: 10,
        durationMin: 60,
        energy: Energy.medium,
      );
      expect(roundTrip(rule.toJson(), MappingRule.fromJson), rule);
      const plain = MappingRule(
        field: MatchField.calendar,
        pattern: 'Cours',
        categoryId: 'teaching',
      );
      expect(plain.priority, 0);
      expect(roundTrip(plain.toJson(), MappingRule.fromJson), plain);
    });
  });

  group('FreeBlock', () {
    test('length and JSON', () {
      final b = FreeBlock(
        start: DateTime.utc(2026, 11, 9, 7),
        end: DateTime.utc(2026, 11, 9, 9, 30),
      );
      expect(b.length, const Duration(hours: 2, minutes: 30));
      expect(roundTrip(b.toJson(), FreeBlock.fromJson), b);
    });

    test('rejects end before start', () {
      expect(
        () => FreeBlock(
          start: DateTime.utc(2026, 11, 9, 9),
          end: DateTime.utc(2026, 11, 9, 8),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Activity', () {
    test('round-trips JSON', () {
      final a = Activity(
        id: 'a1',
        title: 'Deep research block',
        categoryId: 'research',
        durationMin: 90,
        energy: Energy.high,
        source: ActivitySource.template,
      );
      expect(roundTrip(a.toJson(), Activity.fromJson), a);
      final b = Activity(
        id: 'a2',
        title: 'Review paper',
        categoryId: 'research',
        durationMin: 45,
        energy: Energy.medium,
        source: ActivitySource.teachingPrep,
        due: DateTime.utc(2026, 11, 12),
        refId: 't1',
      );
      expect(roundTrip(b.toJson(), Activity.fromJson), b);
    });
  });

  group('Nudge', () {
    test('round-trips JSON', () {
      final n = Nudge(
        id: 'read-paper',
        title: 'Read a paper',
        categoryId: 'reading',
        schedule: Schedule(
          weekdays: const {1, 2, 3, 4, 5},
          period: SchedulePeriod.day,
        ),
        window: TimeWindow(const LocalTime(9, 0), const LocalTime(11, 0)),
        minMinutes: 30,
        durationMin: 45,
      );
      expect(roundTrip(n.toJson(), Nudge.fromJson), n);
      expect(n.toJson()['schedule'], {
        'weekdays': [1, 2, 3, 4, 5],
        'period': 'day',
      });
    });

    test('schedule rejects invalid weekdays', () {
      expect(
        () => Schedule(weekdays: const {0}, period: SchedulePeriod.week),
        throwsArgumentError,
      );
      expect(
        () => Schedule.fromJson({
          'weekdays': [8],
          'period': 'week',
        }),
        throwsFormatException,
      );
    });
  });

  group('FocusSession', () {
    test('round-trips JSON', () {
      final s = FocusSession(
        id: 's1',
        activityId: 'a1',
        categoryId: 'research',
        start: DateTime.utc(2026, 11, 9, 8),
        end: DateTime.utc(2026, 11, 9, 9, 30),
        completed: true,
        note: 'good',
      );
      expect(roundTrip(s.toJson(), FocusSession.fromJson), s);
      expect(s.duration, const Duration(minutes: 90));
    });
  });
}
