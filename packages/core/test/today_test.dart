import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _clock = FakeClock(z(2026, 1, 1));

/// Defaults plus "calendar Cours → teaching" and "list PhD → research".
final config = AppConfig.defaults(clock: _clock).copyWith(
  rules: const [
    MappingRule(
      field: MatchField.calendar,
      pattern: 'Cours',
      categoryId: 'teaching',
    ),
    MappingRule(field: MatchField.list, pattern: 'PhD', categoryId: 'research'),
  ],
);

TaskItem task(
  String uid, {
  DateTime? due,
  String listName = 'PhD',
  bool completed = false,
  int? priority,
}) => TaskItem(
  uid: uid,
  title: uid,
  listName: listName,
  tags: const [],
  due: due,
  priority: priority,
  completed: completed,
);

/// Monday 9 Nov 2026 (CET, UTC+1), at [h]:[min] Paris time.
TodayView monday(
  int h,
  int min, {
  List<CalEvent> events = const [],
  List<TaskItem> tasks = const [],
  AppConfig? cfg,
}) => buildToday(
  config: cfg ?? config,
  events: events,
  tasks: tasks,
  now: p(2026, 11, 9, h, min),
  zone: paris,
);

void main() {
  group('TodayWindow', () {
    test('covers the local day and looks ahead for the inbox', () {
      final w = TodayWindow.of(p(2026, 11, 9, 0, 30), paris);
      expect(w.date, DateTime.utc(2026, 11, 9));
      expect(w.dayStart, p(2026, 11, 9));
      expect(w.dayEnd, p(2026, 11, 10));
      expect(w.fetchEnd, p(2026, 11, 9 + inboxLookaheadDays));
    });

    test('just before local midnight is still the same day', () {
      final w = TodayWindow.of(p(2026, 11, 9, 23, 59), paris);
      expect(w.date, DateTime.utc(2026, 11, 9));
    });

    test('a DST change day is 25 hours long', () {
      final w = TodayWindow.of(p(2026, 10, 25, 12), paris);
      expect(w.dayEnd.difference(w.dayStart), const Duration(hours: 25));
    });
  });

  group('timeline', () {
    test('mixes events and remaining free blocks, sorted by start', () {
      final v = monday(
        8,
        0,
        events: [
          event(
            p(2026, 11, 9, 14),
            p(2026, 11, 9, 16),
            uid: 'lecture',
            calendarName: 'Cours',
          ),
          event(p(2026, 11, 9, 10), p(2026, 11, 9, 11), uid: 'meet'),
        ],
      );
      expect(
        v.timeline.map(
          (e) => switch (e) {
            EventEntry(:final event) => event.uid,
            FreeEntry(:final block) =>
              'free ${formatClock(block.start, paris)}–'
                  '${formatClock(block.end, paris)}',
          },
        ),
        [
          'free 08:00–09:55',
          'meet',
          'free 11:05–13:55',
          'lecture',
          'free 16:05–19:00',
        ],
      );
    });

    test('events carry their category; unmatched ones have none', () {
      final v = monday(
        8,
        0,
        events: [
          event(
            p(2026, 11, 9, 9),
            p(2026, 11, 9, 10),
            uid: 'a',
            calendarName: 'cours',
          ),
          event(p(2026, 11, 9, 11), p(2026, 11, 9, 12), uid: 'b'),
        ],
      );
      final events = v.timeline.whereType<EventEntry>().toList();
      expect(events[0].category?.id, 'teaching');
      expect(events[0].classification?.rule.pattern, 'Cours');
      expect(events[1].category, isNull);
      expect(events[1].classification, isNull);
    });

    test('free blocks start at now; past free time is gone', () {
      final v = monday(17, 0);
      expect(v.free, [
        FreeBlock(start: p(2026, 11, 9, 17), end: p(2026, 11, 9, 19)),
      ]);
      expect(v.freeRemaining, const Duration(hours: 2));
    });

    test('the rest of a block shorter than the minimum is dropped', () {
      expect(monday(18, 50).free, isEmpty);
      expect(monday(18, 50).freeRemaining, Duration.zero);
    });

    test('statuses and the now index follow the clock', () {
      final v = monday(
        10,
        30,
        events: [
          event(p(2026, 11, 9, 8), p(2026, 11, 9, 9), uid: 'past'),
          event(p(2026, 11, 9, 10), p(2026, 11, 9, 11), uid: 'now'),
          event(p(2026, 11, 9, 15), p(2026, 11, 9, 16), uid: 'later'),
        ],
      );
      final byUid = {
        for (final e in v.timeline.whereType<EventEntry>()) e.event.uid: e,
      };
      expect(byUid['past']!.status, TimeStatus.past);
      expect(byUid['now']!.status, TimeStatus.current);
      expect(byUid['later']!.status, TimeStatus.upcoming);
      expect(v.timeline[v.nowIndex], byUid['now']);
      expect(v.timeline.take(v.nowIndex), [byUid['past']]);
    });

    test('now index is the length when the day is over', () {
      final v = monday(
        23,
        0,
        events: [event(p(2026, 11, 9, 8), p(2026, 11, 9, 9))],
      );
      expect(v.nowIndex, v.timeline.length);
    });

    test('events from other days are left out; overnight ones stay', () {
      final v = monday(
        8,
        0,
        events: [
          event(p(2026, 11, 10, 9), p(2026, 11, 10, 10), uid: 'tomorrow'),
          event(p(2026, 11, 8, 9), p(2026, 11, 8, 10), uid: 'yesterday'),
          event(p(2026, 11, 8, 23), p(2026, 11, 9, 1), uid: 'overnight'),
        ],
      );
      expect(v.timeline.whereType<EventEntry>().map((e) => e.event.uid), [
        'overnight',
      ]);
    });

    test('a transparent event is shown but does not take free time', () {
      final v = monday(
        8,
        0,
        events: [
          event(p(2026, 11, 9, 9), p(2026, 11, 9, 10), busy: false, uid: 't'),
        ],
      );
      expect(v.free, [
        FreeBlock(start: p(2026, 11, 9, 8), end: p(2026, 11, 9, 19)),
      ]);
      expect(v.timeline.whereType<EventEntry>().single.event.uid, 't');
    });

    test('on equal starts, events come before free blocks', () {
      final v = monday(
        8,
        0,
        cfg: config.copyWith(
          freeBlocks: FreeBlockSettings(
            workingHours: WorkingHours.weekdays([w('08:00', '19:00')]),
            bufferMin: 0,
            minBlockMin: 15,
          ),
        ),
        events: [event(p(2026, 11, 9, 8), p(2026, 11, 9, 8, 30), busy: false)],
      );
      expect(v.timeline.first, isA<EventEntry>());
      expect(v.timeline[1], isA<FreeEntry>());
    });

    test('no free blocks when the events could not be loaded', () {
      final v = buildToday(
        config: config,
        events: const [],
        eventsLoaded: false,
        tasks: const [],
        now: p(2026, 11, 9, 8),
        zone: paris,
      );
      expect(v.free, isEmpty);
      expect(v.freeKnown, isFalse);
      expect(monday(8, 0).freeKnown, isTrue);
    });

    test('a weekend day has events but no free blocks', () {
      final v = buildToday(
        config: config,
        events: [event(p(2026, 11, 8, 11), p(2026, 11, 8, 12))],
        tasks: const [],
        now: p(2026, 11, 8, 9),
        zone: paris,
      );
      expect(v.free, isEmpty);
      expect(v.timeline, hasLength(1));
    });
  });

  group('all-day events', () {
    test('are listed apart, only when they cover today', () {
      final v = monday(
        8,
        0,
        events: [
          allDay(DateTime.utc(2026, 11, 9), DateTime.utc(2026, 11, 10)),
          allDay(
            DateTime.utc(2026, 11, 6),
            DateTime.utc(2026, 11, 12),
            uid: 'conf',
          ),
          allDay(
            DateTime.utc(2026, 11, 10),
            DateTime.utc(2026, 11, 11),
            uid: 'tomorrow',
          ),
          allDay(
            DateTime.utc(2026, 11, 8),
            DateTime.utc(2026, 11, 9),
            uid: 'yesterday',
          ),
        ],
      );
      expect(v.allDay.map((e) => e.event.uid), ['a', 'conf']);
      expect(v.timeline.whereType<EventEntry>(), isEmpty);
    });

    test('a busy all-day event removes the free blocks', () {
      final v = monday(
        8,
        0,
        events: [allDay(DateTime.utc(2026, 11, 9), DateTime.utc(2026, 11, 10))],
      );
      expect(v.free, isEmpty);
      expect(v.allDay.single.status, TimeStatus.current);
    });
  });

  group('due tasks', () {
    test('open tasks due within three local days, overdue first', () {
      final v = monday(
        10,
        0,
        tasks: [
          task('in3days', due: p(2026, 11, 12, 9)),
          task('dayAfter', due: endOfLocalDate(DateTime(2026, 11, 11), paris)),
          task('today', due: p(2026, 11, 9, 18)),
          task('late', due: p(2026, 11, 2, 9)),
          task('earlierToday', due: p(2026, 11, 9, 9)),
          task('noDue'),
          task('done', due: p(2026, 11, 9, 9), completed: true),
        ],
      );
      expect(v.dueTasks.map((t) => t.task.uid), [
        'late',
        'earlierToday',
        'today',
        'dayAfter',
      ]);
      expect(v.dueTasks.map((t) => t.overdue), [true, true, false, false]);
    });

    test('same due time: higher priority first, undefined last', () {
      final due = p(2026, 11, 9, 18);
      final v = monday(
        10,
        0,
        tasks: [
          task('none', due: due),
          task('low', due: due, priority: 9),
          task('high', due: due, priority: 1),
        ],
      );
      expect(v.dueTasks.map((t) => t.task.uid), ['high', 'low', 'none']);
    });

    group('overdue cap', () {
      final tasks = [
        for (var d = 1; d <= 12; d++) task('late$d', due: p(2026, 10, d, 9)),
        task('today', due: p(2026, 11, 9, 18)),
      ];

      test('shows the 10 most recent overdue tasks, then the rest', () {
        final v = monday(10, 0, tasks: tasks);
        expect(v.dueTasks, hasLength(13));
        final shown = v.visibleDueTasks(showAllOverdue: false);
        expect(shown.hiddenOverdue, 2);
        expect(shown.tasks.map((t) => t.task.uid), [
          for (var d = 3; d <= 12; d++) 'late$d',
          'today',
        ]);
        final all = v.visibleDueTasks(showAllOverdue: true);
        expect(all.hiddenOverdue, 0);
        expect(all.tasks, v.dueTasks);
      });

      test('nothing hidden at or under the cap', () {
        final v = monday(10, 0, tasks: tasks.skip(2).toList());
        expect(v.visibleDueTasks(showAllOverdue: false).hiddenOverdue, 0);
        expect(maxOverdueShown, 10);
      });
    });

    test('tasks carry their category', () {
      final v = monday(
        10,
        0,
        tasks: [
          task('a', due: p(2026, 11, 9, 18)),
          task('b', due: p(2026, 11, 9, 18), listName: 'Home'),
        ],
      );
      expect(v.dueTasks.map((t) => t.category?.id), ['research', null]);
    });
  });

  test('a rule pointing at a deleted category leaves items unclassified', () {
    final cfg = config.copyWith(
      categories: [
        for (final c in config.categories)
          if (c.id != 'teaching') c,
      ],
    );
    final v = monday(
      8,
      0,
      cfg: cfg,
      events: [
        event(p(2026, 11, 9, 9), p(2026, 11, 9, 10), calendarName: 'Cours'),
      ],
    );
    expect(v.timeline.whereType<EventEntry>().single.category, isNull);
  });
}
