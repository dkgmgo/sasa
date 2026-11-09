import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

final base = AppConfig.defaults(clock: FakeClock(z(2026, 11, 1)));

const cours = MappingRule(
  field: MatchField.calendar,
  pattern: 'Cours',
  categoryId: 'teaching',
);
const phd = MappingRule(
  field: MatchField.list,
  pattern: 'PhD',
  categoryId: 'research',
);

void main() {
  group('applyConfigEdit', () {
    test('applies the edit and stamps updatedAt with the clock', () {
      final clock = FakeClock(z(2026, 11, 9, 10));
      final out = applyConfigEdit(base, ConfigEdits.addRule(cours), clock);
      expect(out.rules, [cours]);
      expect(out.updatedAt, z(2026, 11, 9, 10));
    });

    test('updatedAt always moves forward, even with a clock behind', () {
      final ahead = base.copyWith(updatedAt: z(2026, 12, 1));
      final clock = FakeClock(z(2026, 11, 9));
      final out = applyConfigEdit(ahead, ConfigEdits.addRule(cours), clock);
      expect(out.updatedAt.isAfter(ahead.updatedAt), isTrue);
    });
  });

  group('rules', () {
    test('addRule appends and ignores an identical rule', () {
      var c = ConfigEdits.addRule(cours)(base);
      c = ConfigEdits.addRule(phd)(c);
      c = ConfigEdits.addRule(cours)(c);
      expect(c.rules, [cours, phd]);
    });

    test('replaceRule keeps the position', () {
      final c = base.copyWith(rules: [cours, phd]);
      const moved = MappingRule(
        field: MatchField.calendar,
        pattern: 'Cours',
        categoryId: 'admin',
        priority: 3,
      );
      expect(ConfigEdits.replaceRule(cours, moved)(c).rules, [moved, phd]);
    });

    test('replaceRule and removeRule fail when the rule is gone', () {
      final c = base.copyWith(rules: [phd]);
      expect(
        () => ConfigEdits.replaceRule(cours, phd)(c),
        throwsA(isA<ConfigEditConflict>()),
      );
      expect(
        () => ConfigEdits.removeRule(cours)(c),
        throwsA(isA<ConfigEditConflict>()),
      );
    });

    test('removeRule removes one copy', () {
      final c = base.copyWith(rules: [cours, phd]);
      expect(ConfigEdits.removeRule(cours)(c).rules, [phd]);
    });
  });

  group('categories', () {
    test('putCategory replaces by id or appends', () {
      final reading = base.categoryById('reading')!.copyWith(name: 'Papers');
      final c1 = ConfigEdits.putCategory(reading)(base);
      expect(c1.categories.first.name, 'Papers');
      expect(c1.categories, hasLength(base.categories.length));

      final sport = Category(
        id: newCategoryId(base, 'Sport & health'),
        name: 'Sport & health',
        color: '#00897B',
        weeklyTargetMin: 0,
        defaultEnergy: Energy.medium,
        defaultDurationMin: 30,
      );
      final c2 = ConfigEdits.putCategory(sport)(base);
      expect(c2.categories.last.id, 'sport-health');
    });

    test('removeCategory drops its rules too', () {
      final c = base.copyWith(rules: [cours, phd]);
      final out = ConfigEdits.removeCategory('teaching')(c);
      expect(out.categoryById('teaching'), isNull);
      expect(out.rules, [phd]);
    });

    test('removeCategory fails when it is already gone', () {
      expect(
        () => ConfigEdits.removeCategory('nope')(base),
        throwsA(isA<ConfigEditConflict>()),
      );
    });

    test('newCategoryId is a unique slug', () {
      expect(newCategoryId(base, 'Reading'), 'reading-2');
      expect(newCategoryId(base, 'Écriture  Blog!'), 'ecriture-blog');
      expect(newCategoryId(base, '!!!'), 'category');
      final two = base.copyWith(
        categories: [
          ...base.categories,
          const Category(
            id: 'reading-2',
            name: 'Reading again',
            color: '#000000',
            weeklyTargetMin: 0,
            defaultEnergy: Energy.low,
            defaultDurationMin: 30,
          ),
        ],
      );
      expect(newCategoryId(two, 'reading'), 'reading-3');
    });
  });

  group('categoryProblems', () {
    final ok = base.categories.first;

    test('none for a valid category', () {
      expect(categoryProblems(ok, base), isEmpty);
    });

    test('lists every problem', () {
      const bad = Category(
        id: 'new',
        name: '  research ',
        color: 'blue',
        weeklyTargetMin: -1,
        defaultEnergy: Energy.low,
        defaultDurationMin: 0,
      );
      expect(categoryProblems(bad, base), {
        CategoryProblem.duplicateName,
        CategoryProblem.badColor,
        CategoryProblem.negativeTarget,
        CategoryProblem.badDuration,
      });
      expect(categoryProblems(ok.copyWith(name: ' '), base), {
        CategoryProblem.emptyName,
      });
    });

    test('keeping its own name is not a duplicate', () {
      expect(categoryProblems(ok.copyWith(color: '#000000'), base), isEmpty);
    });
  });

  group('ruleProblems', () {
    test('none for a valid rule', () {
      expect(ruleProblems(cours, base), isEmpty);
    });

    test('empty pattern, bad regex, missing category, bad duration', () {
      expect(
        ruleProblems(
          const MappingRule(
            field: MatchField.calendar,
            pattern: ' ',
            categoryId: 'gone',
            durationMin: 0,
          ),
          base,
        ),
        {
          RuleProblem.emptyPattern,
          RuleProblem.unknownCategory,
          RuleProblem.badDuration,
        },
      );
      expect(
        ruleProblems(
          const MappingRule(
            field: MatchField.titleRegex,
            pattern: '(unclosed',
            categoryId: 'admin',
          ),
          base,
        ),
        {RuleProblem.badRegex},
      );
    });
  });

  group('colours', () {
    test('parseHexColor reads #RRGGBB as opaque ARGB', () {
      expect(parseHexColor('#1565C0'), 0xFF1565C0);
      expect(parseHexColor('#c6b328'), 0xFFC6B328);
      expect(parseHexColor('1565C0'), isNull);
      expect(parseHexColor('#12345'), isNull);
      expect(parseHexColor('#GGGGGG'), isNull);
    });

    test('defaults use the coastal palette', () {
      expect(
        {for (final c in defaultCategories()) c.id: c.color},
        {
          'reading': '#F3E3C3',
          'research': '#FF7A5C',
          'writing': '#0B7474',
          'news': '#FFC9B8',
          'teaching': '#BDE7EC',
          'admin': '#0E3B43',
        },
      );
      expect(categoryPalette, hasLength(12));
      expect(categoryPalette.toSet(), hasLength(12));
    });

    test('the palette is valid and includes the default colours', () {
      expect(categoryPalette.every((c) => parseHexColor(c) != null), isTrue);
      for (final c in defaultCategories()) {
        expect(
          categoryPalette.map((p) => p.toLowerCase()),
          contains(c.color.toLowerCase()),
        );
      }
    });
  });

  group('inbox ignore', () {
    const toBuy = InboxIgnore(field: MatchField.list, name: 'To Buy');

    test('ignore adds once; names compare like rules', () {
      var c = ConfigEdits.ignoreInInbox(toBuy)(base);
      c = ConfigEdits.ignoreInInbox(
        const InboxIgnore(field: MatchField.list, name: ' to buy '),
      )(c);
      expect(c.inboxIgnored, [toBuy]);
    });

    test('a calendar and a list with the same name are different', () {
      final c = ConfigEdits.ignoreInInbox(
        const InboxIgnore(field: MatchField.calendar, name: 'To Buy'),
      )(ConfigEdits.ignoreInInbox(toBuy)(base));
      expect(c.inboxIgnored, hasLength(2));
    });

    test('unignore removes it; already gone is fine', () {
      final c = ConfigEdits.ignoreInInbox(toBuy)(base);
      expect(
        ConfigEdits.unignoreInInbox(
          const InboxIgnore(field: MatchField.list, name: 'TO BUY'),
        )(c).inboxIgnored,
        isEmpty,
      );
      expect(ConfigEdits.unignoreInInbox(toBuy)(base).inboxIgnored, isEmpty);
    });

    test('only calendars and lists can be ignored', () {
      expect(
        () => InboxIgnore(field: MatchField.tag, name: 'x'),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
