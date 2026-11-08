import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final categories = defaultCategories();

TaskItem task({
  String title = 'Task',
  String listName = 'Inbox',
  List<String> tags = const [],
  String uid = 't',
}) => TaskItem(
  uid: uid,
  title: title,
  listName: listName,
  tags: tags,
  completed: false,
);

CalEvent ev({String title = 'Event', String calendarName = 'Personal'}) =>
    event(
      z(2026, 11, 9, 9),
      z(2026, 11, 9, 10),
      title: title,
      calendarName: calendarName,
    );

void main() {
  group('matching fields', () {
    test('calendar rule matches event calendar, case-insensitively', () {
      final c = Categoriser(
        rules: const [
          MappingRule(
            field: MatchField.calendar,
            pattern: 'Cours',
            categoryId: 'teaching',
          ),
        ],
        categories: categories,
      );
      expect(
        c.classifyEvent(ev(calendarName: 'cours'))?.categoryId,
        'teaching',
      );
      expect(c.classifyEvent(ev(calendarName: 'Cours 2')), isNull);
    });

    test('calendar rule never matches tasks', () {
      final c = Categoriser(
        rules: const [
          MappingRule(
            field: MatchField.calendar,
            pattern: 'Inbox',
            categoryId: 'admin',
          ),
        ],
        categories: categories,
      );
      expect(c.classifyTask(task(listName: 'Inbox')), isNull);
    });

    test('list rule matches task list only', () {
      final c = Categoriser(
        rules: const [
          MappingRule(
            field: MatchField.list,
            pattern: 'PhD',
            categoryId: 'research',
          ),
        ],
        categories: categories,
      );
      expect(c.classifyTask(task(listName: 'phd'))?.categoryId, 'research');
      expect(c.classifyEvent(ev(calendarName: 'PhD')), isNull);
    });

    test('tag rule matches any task tag', () {
      final c = Categoriser(
        rules: const [
          MappingRule(
            field: MatchField.tag,
            pattern: 'blog',
            categoryId: 'writing',
          ),
        ],
        categories: categories,
      );
      expect(
        c.classifyTask(task(tags: const ['draft', 'Blog']))?.categoryId,
        'writing',
      );
      expect(c.classifyTask(task(tags: const ['blogging'])), isNull);
    });

    test('title regex matches events and tasks, case-insensitively', () {
      final c = Categoriser(
        rules: const [
          MappingRule(
            field: MatchField.titleRegex,
            pattern: r'\blab\b',
            categoryId: 'teaching',
          ),
        ],
        categories: categories,
      );
      expect(
        c.classifyEvent(ev(title: 'Lab Networks'))?.categoryId,
        'teaching',
      );
      expect(
        c.classifyTask(task(title: 'Prepare lab sockets'))?.categoryId,
        'teaching',
      );
      expect(c.classifyTask(task(title: 'Collaborate')), isNull);
    });

    test('invalid regex never matches and does not throw', () {
      final c = Categoriser(
        rules: const [
          MappingRule(
            field: MatchField.titleRegex,
            pattern: '(',
            categoryId: 'admin',
          ),
          MappingRule(
            field: MatchField.titleRegex,
            pattern: '.',
            categoryId: 'news',
          ),
        ],
        categories: categories,
      );
      expect(c.classifyTask(task(title: '(')), isNotNull);
      expect(c.classifyTask(task(title: '('))!.categoryId, 'news');
    });
  });

  group('priority', () {
    test('higher priority wins regardless of list order', () {
      final c = Categoriser(
        rules: const [
          MappingRule(
            field: MatchField.calendar,
            pattern: 'Personal',
            categoryId: 'admin',
          ),
          MappingRule(
            field: MatchField.titleRegex,
            pattern: 'seminar',
            categoryId: 'research',
            priority: 10,
          ),
        ],
        categories: categories,
      );
      expect(c.classifyEvent(ev(title: 'Seminar'))?.categoryId, 'research');
      expect(c.classifyEvent(ev(title: 'Dentist'))?.categoryId, 'admin');
    });

    test('equal priority: first rule in list order wins', () {
      final rules = [
        for (final id in ['reading', 'research', 'writing', 'news', 'admin'])
          MappingRule(
            field: MatchField.titleRegex,
            pattern: '.',
            categoryId: id,
          ),
      ];
      final c = Categoriser(rules: rules, categories: categories);
      expect(c.classifyTask(task())?.categoryId, 'reading');
      expect(
        Categoriser(
          rules: rules.reversed.toList(),
          categories: categories,
        ).classifyTask(task())?.categoryId,
        'admin',
      );
    });

    test('rule pointing at an unknown category is skipped', () {
      final c = Categoriser(
        rules: const [
          MappingRule(
            field: MatchField.titleRegex,
            pattern: '.',
            categoryId: 'deleted',
            priority: 99,
          ),
          MappingRule(
            field: MatchField.titleRegex,
            pattern: '.',
            categoryId: 'admin',
          ),
        ],
        categories: categories,
      );
      expect(c.classifyTask(task())?.categoryId, 'admin');
    });
  });

  group('overrides', () {
    test('rule overrides duration and energy', () {
      final c = Categoriser(
        rules: const [
          MappingRule(
            field: MatchField.list,
            pattern: 'PhD',
            categoryId: 'research',
            durationMin: 25,
            energy: Energy.low,
          ),
        ],
        categories: categories,
      );
      final r = c.classifyTask(task(listName: 'PhD'))!;
      expect(r.durationMin, 25);
      expect(r.energy, Energy.low);
      expect(r.rule.pattern, 'PhD');
    });

    test('falls back to category defaults', () {
      final c = Categoriser(
        rules: const [
          MappingRule(
            field: MatchField.list,
            pattern: 'PhD',
            categoryId: 'research',
          ),
        ],
        categories: categories,
      );
      final research = categories.firstWhere((x) => x.id == 'research');
      final r = c.classifyTask(task(listName: 'PhD'))!;
      expect(r.durationMin, research.defaultDurationMin);
      expect(r.energy, research.defaultEnergy);
    });
  });

  group('batches and the unclassified bucket', () {
    final c = Categoriser(
      rules: const [
        MappingRule(
          field: MatchField.calendar,
          pattern: 'Cours',
          categoryId: 'teaching',
        ),
        MappingRule(
          field: MatchField.list,
          pattern: 'PhD',
          categoryId: 'research',
        ),
      ],
      categories: categories,
    );

    test('events split into classified and unclassified, order kept', () {
      final a = ev(title: 'A', calendarName: 'Cours');
      final bEv = ev(title: 'B', calendarName: 'Other');
      final cEv = ev(title: 'C', calendarName: 'Cours');
      final batch = c.events([a, bEv, cEv]);
      expect(batch.classified.map((x) => x.item), [a, cEv]);
      expect(batch.classified.map((x) => x.classification.categoryId), [
        'teaching',
        'teaching',
      ]);
      expect(batch.unclassified, [bEv]);
    });

    test('tasks split into classified and unclassified', () {
      final a = task(uid: 'a', listName: 'PhD');
      final bT = task(uid: 'b', listName: 'Groceries');
      final batch = c.tasks([a, bT]);
      expect(batch.classified.single.item, a);
      expect(batch.unclassified, [bT]);
    });

    test('no rules: everything is unclassified', () {
      final empty = Categoriser(rules: const [], categories: categories);
      expect(empty.events([ev()]).unclassified, hasLength(1));
      expect(empty.tasks([task()]).classified, isEmpty);
    });
  });

  group('one-tap rule from an unclassified item', () {
    test('event gives a calendar rule that then matches it', () {
      final e = ev(calendarName: 'Cours');
      final rule = ruleForEvent(e, categoryId: 'teaching');
      expect(rule.field, MatchField.calendar);
      expect(rule.pattern, 'Cours');
      final c = Categoriser(rules: [rule], categories: categories);
      expect(c.classifyEvent(e)?.categoryId, 'teaching');
    });

    test('task gives a list rule that then matches it', () {
      final t = task(listName: 'Blog ideas');
      final rule = ruleForTask(t, categoryId: 'writing', priority: 3);
      expect(rule.field, MatchField.list);
      expect(rule.priority, 3);
      final c = Categoriser(rules: [rule], categories: categories);
      expect(c.classifyTask(t)?.categoryId, 'writing');
    });
  });
}
