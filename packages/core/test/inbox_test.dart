import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final config = AppConfig.defaults(clock: FakeClock(z(2026, 1, 1))).copyWith(
  rules: const [
    MappingRule(
      field: MatchField.calendar,
      pattern: 'Cours',
      categoryId: 'teaching',
    ),
  ],
);

TaskItem task(
  String uid, {
  String listName = 'Inbox',
  List<String> tags = const [],
  bool completed = false,
  String? title,
}) => TaskItem(
  uid: uid,
  title: title ?? uid,
  listName: listName,
  tags: tags,
  completed: completed,
);

CalEvent ev(String uid, String calendar, {int day = 9, String? title}) => event(
  z(2026, 11, day, 9),
  z(2026, 11, day, 10),
  uid: uid,
  title: title ?? uid,
  calendarName: calendar,
);

void main() {
  group('buildInbox', () {
    test('groups unclassified events by calendar and tasks by list', () {
      final inbox = buildInbox(
        config: config,
        events: [
          ev('a', 'Personal'),
          ev('lecture', 'Cours'),
          ev('b', 'Seminars'),
          ev('c', 'personal'),
        ],
        tasks: [
          task('t1'),
          task('t2', listName: 'Home'),
          task('t3'),
        ],
      );
      expect(
        inbox.groups.map(
          (g) =>
              '${g.field.name}:${g.name}:${g.events.length + g.tasks.length}',
        ),
        // Biggest first, then by name; calendar names compare like the rules.
        [
          'list:Inbox:2',
          'calendar:Personal:2',
          'list:Home:1',
          'calendar:Seminars:1',
        ],
      );
      expect(inbox.itemCount, 6);
      expect(inbox.isEmpty, isFalse);
    });

    test('recurring instances count once, the earliest kept', () {
      final inbox = buildInbox(
        config: config,
        events: [
          ev('weekly', 'Personal', day: 16, title: 'later'),
          ev('weekly', 'Personal', title: 'first'),
        ],
        tasks: const [],
      );
      final g = inbox.groups.single;
      expect(g.events.single.title, 'first');
    });

    test('completed tasks and classified items stay out', () {
      final inbox = buildInbox(
        config: config,
        events: [ev('lecture', 'Cours')],
        tasks: [task('done', completed: true)],
      );
      expect(inbox.isEmpty, isTrue);
      expect(inbox.itemCount, 0);
    });

    test("a group's rule classifies every item in it", () {
      final events = [ev('a', 'Personal'), ev('b', 'personal')];
      final tasks = [task('t', listName: 'Home')];
      final inbox = buildInbox(config: config, events: events, tasks: tasks);
      var cfg = config;
      for (final g in inbox.groups) {
        cfg = ConfigEdits.addRule(g.ruleFor('admin'))(cfg);
      }
      expect(
        buildInbox(config: cfg, events: events, tasks: tasks).isEmpty,
        isTrue,
      );
      final rule = inbox.groups.first.ruleFor('admin');
      expect(rule.field, MatchField.calendar);
      expect(rule.pattern, 'Personal');
    });
  });

  group('rule choices', () {
    test('for an event: its calendar, then its exact title', () {
      final e = ev('a', 'Personal', title: 'Lab meeting (weekly)');
      final choices = ruleChoicesForEvent(e, categoryId: 'research');
      expect(choices.map((r) => r.field), [
        MatchField.calendar,
        MatchField.titleRegex,
      ]);
      final byTitle = choices.last;
      expect(byTitle.pattern, r'^Lab meeting \(weekly\)$');
      final c = Categoriser(rules: [byTitle], categories: config.categories);
      expect(c.classifyEvent(e)?.categoryId, 'research');
      expect(c.classifyEvent(ev('b', 'X', title: 'Lab meeting')), isNull);
      // A title rule beats a calendar rule on the same item.
      expect(byTitle.priority, greaterThan(choices.first.priority));
    });

    test('for a task: its list, each tag, then its title', () {
      final t = task('t', listName: 'PhD', tags: ['read', 'cs'], title: 'Q');
      final choices = ruleChoicesForTask(t, categoryId: 'reading');
      expect(choices.map(describeMatch), [
        'List is “PhD”',
        'Tag is “read”',
        'Tag is “cs”',
        'Title matches /^Q\$/',
      ]);
      expect(choices.every((r) => r.categoryId == 'reading'), isTrue);
      expect(choices[1].priority, greaterThan(choices[0].priority));
      expect(choices[3].priority, greaterThan(choices[1].priority));
    });

    test('a title is trimmed before it is escaped', () {
      expect(ruleForTitle('  a.b ', categoryId: 'x').pattern, r'^a\.b$');
    });
  });

  group('previewRule', () {
    test('lists the distinct items one rule would match', () {
      final preview = previewRule(
        const MappingRule(
          field: MatchField.titleRegex,
          pattern: 'seminar',
          categoryId: 'research',
        ),
        events: [
          ev('s', 'Talks', title: 'Team seminar'),
          ev('s', 'Talks', day: 16, title: 'Team seminar'),
          ev('x', 'Talks', title: 'Lunch'),
        ],
        tasks: [
          task('t', title: 'Prepare seminar slides'),
          task('done', title: 'Old seminar', completed: true),
        ],
      );
      expect(preview.events.map((e) => e.uid), ['s']);
      expect(preview.tasks.map((t) => t.uid), ['t']);
      expect(preview.count, 2);
    });

    test('an invalid rule matches nothing', () {
      final preview = previewRule(
        const MappingRule(
          field: MatchField.titleRegex,
          pattern: '(',
          categoryId: 'research',
        ),
        events: [ev('a', 'Talks')],
        tasks: const [],
      );
      expect(preview.count, 0);
    });
  });

  group('ignored groups', () {
    test('leave the inbox count but stay listed apart', () {
      final cfg = ConfigEdits.ignoreInInbox(
        const InboxIgnore(field: MatchField.list, name: 'home'),
      )(config);
      final inbox = buildInbox(
        config: cfg,
        events: [ev('a', 'Personal')],
        tasks: [
          task('t1', listName: 'Home'),
          task('t2', listName: 'Home'),
        ],
      );
      expect(inbox.groups.map((g) => g.name), ['Personal']);
      expect(inbox.itemCount, 1);
      expect(inbox.ignored.single.name, 'Home');
      expect(inbox.ignored.single.count, 2);
      expect(inbox.ignored.single.ignoreKey, cfg.inboxIgnored.single);
    });

    test('everything ignored counts as empty', () {
      final cfg = ConfigEdits.ignoreInInbox(
        const InboxIgnore(field: MatchField.calendar, name: 'Personal'),
      )(config);
      final inbox = buildInbox(
        config: cfg,
        events: [ev('a', 'Personal')],
        tasks: const [],
      );
      expect(inbox.isEmpty, isTrue);
      expect(inbox.ignored, hasLength(1));
    });
  });
}
