import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Working hours 08:30–12:30 and 14:00–19:00 on weekdays, no buffer, and
/// "calendar Cours → Teaching".
final config = AppConfig.defaults(clock: FakeClock(z(2026, 1, 1))).copyWith(
  freeBlocks: FreeBlockSettings(
    workingHours: WorkingHours.weekdays([
      w('08:30', '12:30'),
      w('14:00', '19:00'),
    ]),
    bufferMin: 0,
    minBlockMin: 15,
  ),
  rules: const [
    MappingRule(
      field: MatchField.calendar,
      pattern: 'Cours',
      categoryId: 'teaching',
    ),
    MappingRule(field: MatchField.list, pattern: 'PhD', categoryId: 'research'),
  ],
);

TaskItem task(String title, DateTime? due, {bool completed = false}) =>
    TaskItem(
      uid: title,
      title: title,
      listName: 'PhD',
      tags: const [],
      due: due,
      completed: completed,
    );

Nudge nudge(String id, Set<int> weekdays) => Nudge(
  id: id,
  title: id,
  categoryId: 'reading',
  schedule: Schedule(weekdays: weekdays, period: SchedulePeriod.day),
  window: w('09:00', '11:00'),
  minMinutes: 30,
  durationMin: 45,
);

/// Monday 9 Nov 2026, as in the example brief.
final mondayEvents = [
  event(
    p(2026, 11, 9, 10, 30),
    p(2026, 11, 9, 12, 30),
    uid: 'tp',
    title: 'Networks lab',
    calendarName: 'Cours',
  ),
  event(p(2026, 11, 9, 14), p(2026, 11, 9, 15), uid: 'm', title: 'Meeting'),
  event(p(2026, 11, 9, 15), p(2026, 11, 9, 15, 15), uid: 's', title: 'Seminar'),
];

void main() {
  final clock = FakeClock(p(2026, 11, 9, 7, 30));
  final renderer = BriefRenderer(clock: clock);

  setUp(() => clock.set(p(2026, 11, 9, 7, 30)));

  Brief render({
    AppConfig? cfg,
    List<CalEvent>? events,
    bool eventsLoaded = true,
    List<TaskItem> tasks = const [],
    DateTime? at,
    BriefSuggestion? suggestFor,
    bool Function(Nudge)? nudgeSatisfied,
  }) => renderer.render(
    config: cfg ?? config,
    events: events ?? mondayEvents,
    eventsLoaded: eventsLoaded,
    tasks: tasks,
    zone: paris,
    at: at,
    suggestFor: suggestFor,
    nudgeSatisfied: nudgeSatisfied,
  );

  test('renders the example brief', () {
    final b = render(
      cfg: config.copyWith(
        nudges: [
          nudge('Read a paper', {1, 2, 3, 4, 5}),
        ],
      ),
      tasks: [task('review for X', p(2026, 11, 9, 18))],
      suggestFor: (block) =>
          block.start == p(2026, 11, 9, 8, 30) ? 'Deep research block' : null,
    );
    expect(b.date, DateTime.utc(2026, 11, 9));
    expect(b.title, 'Sasa! Mon 9 Nov — 3 events · 5 h 45 free');
    expect(b.lines, [
      '08:30–10:30  free (2 h) → suggested: Deep research block',
      '10:30–12:30  Networks lab (Teaching)',
      '14:00–15:00  Meeting',
      '15:00–15:15  Seminar',
      '15:15–19:00  free (3 h 45)',
      'Due: review for X (today) · Nudges: Read a paper',
    ]);
    expect(b.body, b.lines.join('\n'));
    expect(b.text, '${b.title}\n${b.body}');
  });

  test('without a time, describes the rest of the day from the clock', () {
    clock.set(p(2026, 11, 9, 14, 30));
    final b = render();
    expect(b.title, 'Sasa! Mon 9 Nov — 2 events · 3 h 45 free');
    expect(b.lines, [
      '14:00–15:00  Meeting',
      '15:00–15:15  Seminar',
      '15:15–19:00  free (3 h 45)',
    ]);
  });

  test('a brief for a later time describes that day, not the clock\'s', () {
    // Rendered on Sunday evening for Monday morning.
    clock.set(p(2026, 11, 8, 21));
    final b = render(at: p(2026, 11, 9, 7, 30));
    expect(b.date, DateTime.utc(2026, 11, 9));
    expect(b.title, 'Sasa! Mon 9 Nov — 3 events · 5 h 45 free');
    expect(b.lines.first, '08:30–10:30  free (2 h)');
  });

  test('all-day events come first and count as events', () {
    final b = render(
      events: [
        ...mondayEvents,
        CalEvent(
          uid: 'conf',
          title: 'Conference',
          start: DateTime.utc(2026, 11, 9),
          end: DateTime.utc(2026, 11, 10),
          allDay: true,
          busy: false,
          calendarName: 'Cours',
        ),
      ],
    );
    expect(b.title, startsWith('Sasa! Mon 9 Nov — 4 events'));
    expect(b.lines.first, 'All day  Conference (Teaching)');
  });

  test('a day with nothing on it', () {
    final b = render(at: p(2026, 11, 14, 7, 30), events: const []);
    expect(b.title, 'Sasa! Sat 14 Nov — no events');
    expect(b.lines, ['Nothing scheduled.']);
  });

  test('a full working day says there is no free time', () {
    final b = render(
      events: [event(p(2026, 11, 9, 8), p(2026, 11, 9, 19), title: 'Jury')],
    );
    expect(b.title, 'Sasa! Mon 9 Nov — 1 event · no free time');
    expect(b.lines, ['08:00–19:00  Jury']);
  });

  test('when the calendar did not load, says so and still lists tasks', () {
    final b = render(
      events: const [],
      eventsLoaded: false,
      tasks: [task('review for X', p(2026, 11, 9, 18))],
    );
    expect(b.title, 'Sasa! Mon 9 Nov — calendar unavailable');
    expect(b.lines, [
      'Could not load your calendar.',
      'Due: review for X (today)',
    ]);
  });

  group('due tasks', () {
    test('today first, then overdue (newest first), then later', () {
      final b = render(
        tasks: [
          task('later', p(2026, 11, 11, 12)),
          task('old', p(2026, 11, 2, 12)),
          task('recent', p(2026, 11, 8, 12)),
          task('today', endOfLocalDate(DateTime.utc(2026, 11, 9), paris)),
        ],
      );
      expect(
        b.lines.last,
        'Due: today (today), recent (overdue), old (overdue) +1 more',
      );
    });

    test('tomorrow and in N days', () {
      final b = render(
        tasks: [task('a', p(2026, 11, 10, 9)), task('b', p(2026, 11, 11, 9))],
      );
      expect(b.lines.last, 'Due: a (tomorrow), b (in 2 days)');
    });

    test('completed and undated tasks are left out', () {
      final b = render(
        tasks: [
          task('done', p(2026, 11, 9, 9), completed: true),
          task('someday', null),
        ],
      );
      expect(b.lines.where((l) => l.startsWith('Due')), isEmpty);
    });
  });

  group('nudges', () {
    final cfg = config.copyWith(
      nudges: [
        nudge('Read a paper', {1, 2, 3, 4, 5}),
        nudge('Write a blog post', {7}),
        nudge('Veille', {1}),
      ],
    );

    test('lists those scheduled on that weekday', () {
      expect(render(cfg: cfg).lines.last, 'Nudges: Read a paper, Veille');
      expect(
        render(cfg: cfg, at: p(2026, 11, 15, 7, 30)).lines.last,
        'Nudges: Write a blog post',
      );
    });

    test('leaves out the ones already satisfied', () {
      final b = render(cfg: cfg, nudgeSatisfied: (n) => n.id == 'Veille');
      expect(b.lines.last, 'Nudges: Read a paper');
    });
  });

  test('free blocks shorter than the minimum are not listed', () {
    final b = render(
      events: [event(p(2026, 11, 9, 8, 40), p(2026, 11, 9, 19), title: 'Long')],
    );
    expect(b.lines, ['08:40–19:00  Long']);
  });
}
