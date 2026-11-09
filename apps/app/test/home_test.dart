import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/main.dart';
import 'package:sasa/src/category_style.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'fakes.dart';

final paris = locationFor('Europe/Paris');

/// UTC instant of a Paris wall-clock time in November 2026.
DateTime p(int d, int h, [int m = 0]) =>
    utcInstant(tz.TZDateTime(paris, 2026, 11, d, h, m));

CalEvent ev(
  String title,
  String calendar,
  DateTime start,
  DateTime end, {
  bool allDay = false,
  bool busy = true,
}) => CalEvent(
  uid: title,
  title: title,
  start: start,
  end: end,
  allDay: allDay,
  busy: busy,
  calendarName: calendar,
);

TaskItem task(String title, String list, {DateTime? due}) => TaskItem(
  uid: title,
  title: title,
  listName: list,
  tags: const ['urgent'],
  due: due,
  completed: false,
);

const phdRule = MappingRule(
  field: MatchField.calendar,
  pattern: 'PhD',
  categoryId: 'research',
);

/// Name on the category tag of the timeline row titled [title].
String tagOf(WidgetTester tester, String title) {
  final row = find
      .ancestor(of: find.text(title), matching: find.byType(Row))
      .first;
  final tag = find.descendant(of: row, matching: find.byType(CategoryTag));
  return tester.widget<CategoryTag>(tag).category?.name ?? 'Unclassified';
}

void main() {
  late MemoryFolderAccess access;
  late MemoryDeviceSettings settings;

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Monday 9 Nov 2026, 10:30 in Paris, on Linux with a CalDAV fake.
  Future<void> start(
    WidgetTester tester, {
    Size size = const Size(420, 2000),
    List<TaskItem> moreTasks = const [],
    ThemeMode themeMode = ThemeMode.system,
  }) async {
    setSize(tester, size);
    access = MemoryFolderAccess();
    final folder = SasaFolder(access.folder(syncA.ref));
    final clock = FakeClock(p(9, 10, 30));
    await folder.saveConfig(
      AppConfig.defaults(clock: clock).copyWith(rules: [phdRule]),
    );
    final source = FakeSource(
      events: [
        ev('Lab meeting', 'PhD', p(9, 9), p(9, 10)),
        ev('Lecture', 'Cours', p(9, 14), p(9, 16)),
        ev('Seminar', 'Talks', p(9, 16, 30), p(9, 17, 30)),
        ev(
          'Conference week',
          'Talks',
          DateTime.utc(2026, 11, 9),
          DateTime.utc(2026, 11, 14),
          allDay: true,
          busy: false,
        ),
      ],
      tasks: [
        task('Review paper', 'Thesis', due: p(9, 18)),
        task('Send form', 'Paperwork', due: p(6, 12)),
        task('Someday', 'Thesis'),
        ...moreTasks,
      ],
    );
    await tester.pumpWidget(
      SasaApp(
        services: testServices(
          platform: SourcePlatform.linux,
          settings: settings = MemoryDeviceSettings(
            syncFolder: syncA,
            setupDone: true,
            themeMode: themeMode,
          ),
          access: access,
          calDav: source,
          clock: clock,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<AppConfig> saved() async =>
      (await SasaFolder(access.folder(syncA.ref)).loadConfig())!;

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Today', () {
    testWidgets('timeline, free time, all-day events and due tasks', (
      tester,
    ) async {
      await start(tester);
      expect(find.text('Monday 9 November'), findsOneWidget);
      expect(find.text('5 h 10 free today'), findsOneWidget);
      expect(find.text('Conference week'), findsOneWidget);

      expect(find.text('Lab meeting'), findsOneWidget);
      expect(tagOf(tester, 'Lab meeting'), 'Research');
      expect(tagOf(tester, 'Lecture'), 'Unclassified');
      expect(find.text('PhD'), findsOneWidget);
      expect(find.text('Cours'), findsOneWidget);
      expect(find.text('Now 10:30'), findsOneWidget);
      expect(find.text('Free · 3 h 25'), findsOneWidget);
      expect(find.text('13:55'), findsOneWidget);
      expect(find.text('Free · 20 min'), findsOneWidget);
      expect(find.text('Free · 1 h 25'), findsOneWidget);

      // Now marker sits after the past meeting and before the free block.
      final marker = tester.getTopLeft(find.text('Now 10:30')).dy;
      expect(tester.getTopLeft(find.text('Lab meeting')).dy, lessThan(marker));
      expect(
        tester.getTopLeft(find.text('Free · 3 h 25')).dy,
        greaterThan(marker),
      );

      expect(find.text('Review paper'), findsOneWidget);
      expect(find.text('Today 18:00 · Thesis'), findsOneWidget);
      expect(
        find.text('Overdue · Fri 6 Nov 12:00 · Paperwork'),
        findsOneWidget,
      );
      expect(find.text('Someday'), findsNothing);
      expect(find.text('6 unclassified items'), findsOneWidget);
    });

    testWidgets("I'm free is a placeholder for now", (tester) async {
      await start(tester);
      await tester.tap(find.text("I'm free"));
      await tester.pump();
      expect(find.textContaining('later version'), findsOneWidget);
    });

    testWidgets('the unclassified card opens the inbox', (tester) async {
      await start(tester);
      await tester.tap(find.text('6 unclassified items'));
      await tester.pumpAndSettle();
      expect(find.text('Calendar “Talks”'), findsOneWidget);
    });
  });

  group('Inbox', () {
    testWidgets('one tap assigns a whole calendar', (tester) async {
      await start(tester);
      await tab(tester, 'Inbox');
      expect(find.text('Calendar “Talks”'), findsOneWidget);
      expect(find.text('2 events'), findsOneWidget);
      expect(find.text('List “Thesis”'), findsOneWidget);

      final cours = find.ancestor(
        of: find.text('Calendar “Cours”'),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(of: cours, matching: find.text('Assign category')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teaching'));
      await tester.pumpAndSettle();

      expect(
        find.text('Rule added: Calendar is “Cours” → Teaching'),
        findsOneWidget,
      );
      expect(find.text('Calendar “Cours”'), findsNothing);
      expect((await saved()).rules, [
        phdRule,
        const MappingRule(
          field: MatchField.calendar,
          pattern: 'Cours',
          categoryId: 'teaching',
        ),
      ]);

      await tab(tester, 'Today');
      expect(tagOf(tester, 'Lecture'), 'Teaching');
      expect(find.text('5 unclassified items'), findsOneWidget);
    });

    testWidgets('an item can get a tag or title rule', (tester) async {
      await start(tester);
      await tab(tester, 'Inbox');
      await tester.tap(find.text('Send form'));
      await tester.pumpAndSettle();
      expect(find.text('List is “Paperwork”'), findsOneWidget);
      expect(find.text('Title matches /^Send form\$/'), findsOneWidget);
      await tester.tap(find.text('Tag is “urgent”'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();

      final rule = (await saved()).rules.last;
      expect(rule.field, MatchField.tag);
      expect(rule.pattern, 'urgent');
      expect(rule.categoryId, 'admin');
      expect(rule.priority, tagRulePriority);
      // Every task is tagged "urgent": all three left the inbox.
      expect(find.text('List “Thesis”'), findsNothing);
    });

    testWidgets('all classified shows an empty state', (tester) async {
      await start(tester);
      await tab(tester, 'Inbox');
      for (final name in ['Talks', 'Cours']) {
        final card = find.ancestor(
          of: find.text('Calendar “$name”'),
          matching: find.byType(Card),
        );
        await tester.tap(
          find.descendant(of: card, matching: find.text('Assign category')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Research'));
        await tester.pumpAndSettle();
      }
      for (final name in ['Thesis', 'Paperwork']) {
        final card = find.ancestor(
          of: find.text('List “$name”'),
          matching: find.byType(Card),
        );
        await tester.tap(
          find.descendant(of: card, matching: find.text('Assign category')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Admin'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Everything has a category'), findsOneWidget);
    });
  });

  group('Inbox extras', () {
    testWidgets('a long group shows four items, then all', (tester) async {
      await start(
        tester,
        size: const Size(420, 3000),
        moreTasks: [for (var i = 1; i <= 6; i++) task('Buy $i', 'To Buy')],
      );
      await tab(tester, 'Inbox');
      expect(find.text('Buy 4'), findsOneWidget);
      expect(find.text('Buy 5'), findsNothing);
      await tester.tap(find.text('Show all 6'));
      await tester.pumpAndSettle();
      expect(find.text('Buy 6'), findsOneWidget);
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.text('Buy 6'), findsNothing);
    });

    testWidgets('a list can be ignored for now and shown again', (
      tester,
    ) async {
      await start(tester);
      await tab(tester, 'Inbox');
      final thesis = find.ancestor(
        of: find.text('List “Thesis”'),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(of: thesis, matching: find.byTooltip('More')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ignore for now'));
      await tester.pumpAndSettle();

      expect((await saved()).inboxIgnored, const [
        InboxIgnore(field: MatchField.list, name: 'Thesis'),
      ]);
      expect(find.text('Ignored for now (1)'), findsOneWidget);
      // 6 items minus the 2 Thesis tasks.
      expect(find.text('4'), findsOneWidget);

      await tab(tester, 'Today');
      expect(find.text('4 unclassified items'), findsOneWidget);
      await tab(tester, 'Inbox');

      await tester.tap(find.text('Ignored for now (1)'));
      await tester.pumpAndSettle();
      expect(find.text('List “Thesis”'), findsOneWidget);
      await tester.tap(find.text('Show again'));
      await tester.pumpAndSettle();
      expect((await saved()).inboxIgnored, isEmpty);
      expect(find.text('Ignored for now (1)'), findsNothing);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('with everything else classified, ignored lists still show', (
      tester,
    ) async {
      await start(tester);
      await tab(tester, 'Inbox');
      for (final label in [
        'Calendar “Talks”',
        'Calendar “Cours”',
        'List “Thesis”',
        'List “Paperwork”',
      ]) {
        final card = find.ancestor(
          of: find.text(label),
          matching: find.byType(Card),
        );
        await tester.tap(
          find.descendant(of: card, matching: find.byTooltip('More')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ignore for now'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Everything has a category'), findsOneWidget);
      expect(find.text('Ignored for now (4)'), findsOneWidget);
    });
  });

  group('Today overdue cap', () {
    testWidgets('shows 10 recent overdue tasks, then all', (tester) async {
      await start(
        tester,
        size: const Size(420, 4000),
        moreTasks: [
          task('Ancient', 'Backlog', due: p(1, 7)),
          for (var d = 1; d <= 9; d++) task('Old $d', 'Backlog', due: p(d, 8)),
        ],
      );
      // 11 overdue: Ancient (1 Nov 07:00), Old 1…9 and Send form.
      expect(find.text('Ancient'), findsNothing);
      expect(find.text('Old 1'), findsOneWidget);
      await tester.tap(find.text('Show 1 older overdue'));
      await tester.pumpAndSettle();
      expect(find.text('Ancient'), findsOneWidget);
      await tester.tap(find.text('Show recent overdue only'));
      await tester.pumpAndSettle();
      expect(find.text('Ancient'), findsNothing);
    });

    testWidgets('no button when overdue tasks fit', (tester) async {
      await start(tester);
      expect(find.textContaining('older overdue'), findsNothing);
    });
  });

  group('Categories', () {
    testWidgets('edit a category', (tester) async {
      await start(tester);
      await tab(tester, 'Categories');
      expect(
        find.text(
          '15 h a week · 1 h 30 blocks · high energy · best 09:00–12:00',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Reading'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Papers');
      await tester.enterText(
        find.widgetWithText(TextField, 'Weekly target'),
        '10.5',
      );
      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Papers'), findsOneWidget);
      expect(
        find.text('10 h 30 a week · 45 min blocks · high energy'),
        findsOneWidget,
      );
      final reading = (await saved()).categoryById('reading')!;
      expect(reading.name, 'Papers');
      expect(reading.weeklyTargetMin, 630);
      expect(reading.defaultEnergy, Energy.high);
    });

    testWidgets('add a category; a duplicate name cannot be saved', (
      tester,
    ) async {
      await start(tester);
      await tab(tester, 'Categories');
      await tester.tap(find.text('Category'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'admin');
      await tester.pump();
      expect(find.text(CategoryProblem.duplicateName.message), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Sport');
      await tester.tap(find.text('Preferred time of day'));
      await tester.pump();
      expect(find.text('From 09:00'), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final sport = (await saved()).categories.last;
      expect(sport.id, 'sport');
      expect(sport.preferredWindow.toString(), '09:00–12:00');
      expect(find.text('Sport'), findsOneWidget);
    });

    testWidgets('deleting a category removes its rules', (tester) async {
      await start(tester);
      await tab(tester, 'Categories');
      await tester.tap(find.text('Research'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete category'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Its 1 rule will be deleted'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      final config = await saved();
      expect(config.categoryById('research'), isNull);
      expect(config.rules, isEmpty);
      expect(find.text('Research'), findsNothing);
    });
  });

  group('Rules', () {
    testWidgets('add a title rule with a live preview', (tester) async {
      await start(tester);
      await tab(tester, 'Rules');
      expect(find.text('Calendar is “PhD”'), findsOneWidget);
      await tester.tap(find.text('Rule'));
      await tester.pumpAndSettle();

      final pattern = find.widgetWithText(TextField, 'Regular expression');
      await tester.enterText(pattern, '(unclosed');
      await tester.pump();
      expect(find.text(RuleProblem.badRegex.message), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(pattern, 'lecture|seminar');
      await tester.pump();
      expect(find.text('Matches 2 events and 0 tasks.'), findsOneWidget);

      await tester.tap(find.text('Reading').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teaching').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Priority'), '7');
      await tester.enterText(find.widgetWithText(TextField, 'Duration'), '50');
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.text('Title matches /lecture|seminar/'), findsOneWidget);
      // Highest priority first.
      final top = tester.getTopLeft(
        find.text('Title matches /lecture|seminar/'),
      );
      expect(
        top.dy,
        lessThan(tester.getTopLeft(find.text('Calendar is “PhD”')).dy),
      );
      expect(
        (await saved()).rules.last,
        const MappingRule(
          field: MatchField.titleRegex,
          pattern: 'lecture|seminar',
          categoryId: 'teaching',
          priority: 7,
          durationMin: 50,
        ),
      );
    });

    testWidgets('edit and delete a rule', (tester) async {
      await start(tester);
      await tab(tester, 'Rules');
      await tester.tap(find.text('Calendar is “PhD”'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Thesis');
      await tester.tap(find.text('Calendar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Task list').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('List is “Thesis”'), findsOneWidget);
      expect((await saved()).rules.single.field, MatchField.list);

      await tester.tap(find.text('List is “Thesis”'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete rule'));
      await tester.pumpAndSettle();
      expect(find.text('No rules yet'), findsOneWidget);
      expect((await saved()).rules, isEmpty);
    });
  });

  group('load errors', () {
    Future<void> startWithoutAccount(WidgetTester tester) async {
      setSize(tester, const Size(420, 2000));
      access = MemoryFolderAccess();
      await tester.pumpWidget(
        SasaApp(
          services: testServices(
            platform: SourcePlatform.linux,
            settings: MemoryDeviceSettings(syncFolder: syncA, setupDone: true),
            access: access,
            clock: FakeClock(p(9, 10, 30)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('one card when events and tasks fail the same way', (
      tester,
    ) async {
      await startWithoutAccount(tester);
      expect(
        find.text('No CalDAV account yet: add one in Settings.'),
        findsOneWidget,
      );
      expect(
        find.text('Free time unknown: the calendar did not load'),
        findsOneWidget,
      );
      expect(find.textContaining('Free ·'), findsNothing);
    });

    testWidgets('the inbox shows the error, not "all classified"', (
      tester,
    ) async {
      await startWithoutAccount(tester);
      await tab(tester, 'Inbox');
      expect(find.text('Everything has a category'), findsNothing);
      expect(
        find.text('No CalDAV account yet: add one in Settings.'),
        findsOneWidget,
      );
    });
  });

  group('layout and theme', () {
    testWidgets('wide windows use a navigation rail', (tester) async {
      await start(tester, size: const Size(1200, 1600));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('every screen fits a narrow phone', (tester) async {
      await start(tester, size: const Size(360, 1400));
      for (final t in ['Inbox', 'Categories', 'Rules', 'Today']) {
        await tab(tester, t);
      }
      await tab(tester, 'Categories');
      await tester.tap(find.text('Research'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tab(tester, 'Rules');
      await tester.tap(find.text('Calendar is “PhD”'));
      await tester.pumpAndSettle();
      expect(find.text('Edit rule'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the theme can be chosen in settings, per device', (
      tester,
    ) async {
      await start(tester);
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
      expect(brightness(), Brightness.light);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      expect(await settings.themeMode(), ThemeMode.dark);

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      expect(await settings.themeMode(), ThemeMode.system);
    });

    testWidgets('a saved theme is used from the start', (tester) async {
      await start(tester, themeMode: ThemeMode.dark);
      final context = tester.element(find.text('Lab meeting'));
      expect(Theme.of(context).brightness, Brightness.dark);
    });

    testWidgets('follows the system dark mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await start(tester);
      final context = tester.element(find.text('Lab meeting'));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(Theme.of(context).useMaterial3, isTrue);
    });
  });
}
