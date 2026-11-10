import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/main.dart';
import 'package:sasa/src/brief/brief_scheduler.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'fakes.dart';

final paris = locationFor('Europe/Paris');

DateTime p(int d, int h, [int m = 0]) =>
    utcInstant(tz.TZDateTime(paris, 2026, 11, d, h, m));

CalEvent ev(String title, DateTime start, DateTime end) => CalEvent(
  uid: title,
  title: title,
  start: start,
  end: end,
  allDay: false,
  busy: true,
  calendarName: 'PhD',
);

final class _Failing implements CalendarSource {
  @override
  Future<List<CalEvent>> events(DateTime from, DateTime to) async =>
      throw const SourceUnavailable('offline');

  @override
  Future<List<TaskItem>> tasks() async => const [];
}

void main() {
  group('BriefScheduler', () {
    late FakeClock clock;
    late FakeBriefNotifier notifier;
    late BriefScheduler scheduler;
    final config = AppConfig.defaults(clock: FakeClock(p(1, 0)));
    // Monday 9 Nov: a lecture; Tuesday 10 Nov: a seminar.
    final source = FakeSource(
      events: [
        ev('Lecture', p(9, 14), p(9, 16)),
        ev('Seminar', p(10, 10), p(10, 11)),
      ],
    );

    setUp(() {
      clock = FakeClock(p(9, 6)); // Monday 06:00
      notifier = FakeBriefNotifier();
      scheduler = BriefScheduler(notifier: notifier, clock: clock);
    });

    test('schedules the next brief with that day\'s content', () async {
      final s = await scheduler.reschedule(
        config: config,
        source: source,
        zone: paris,
      );
      expect(s.next, p(9, 7, 30));
      final n = notifier.scheduled.single;
      expect(n.at, tz.TZDateTime.from(p(9, 7, 30), paris));
      expect(n.at.location, paris);
      expect(n.exact, isTrue);
      expect(n.title, 'Sasa! Mon 9 Nov — 1 event · 8 h 50 free');
      expect(n.body, contains('14:00–16:00  Lecture'));
      expect(n.title, isNot(contains('\n')));
    });

    test('after the brief time, renders tomorrow\'s brief', () async {
      clock.set(p(9, 8));
      await scheduler.reschedule(config: config, source: source, zone: paris);
      final n = notifier.scheduled.single;
      expect(n.at, tz.TZDateTime.from(p(10, 7, 30), paris));
      expect(n.title, startsWith('Sasa! Tue 10 Nov — 1 event'));
      expect(n.body, contains('Seminar'));
      expect(n.body, isNot(contains('Lecture')));
    });

    test('inexact when exact alarms are not allowed', () async {
      notifier.exact = false;
      final s = await scheduler.reschedule(
        config: config,
        source: source,
        zone: paris,
      );
      expect(s.exact, isFalse);
      expect(notifier.scheduled.single.exact, isFalse);
    });

    test('a disabled brief is cancelled', () async {
      final s = await scheduler.reschedule(
        config: config.copyWith(brief: config.brief.copyWith(enabled: false)),
        source: source,
        zone: paris,
      );
      expect(s.next, isNull);
      expect(notifier.cancels, 1);
      expect(notifier.scheduled, isEmpty);
    });

    test('a calendar failure keeps the brief scheduled before', () async {
      await scheduler.reschedule(config: config, source: source, zone: paris);
      final s = await scheduler.reschedule(
        config: config,
        source: _Failing(),
        zone: paris,
      );
      expect(s.kept, isNotNull);
      expect(notifier.scheduled, hasLength(1));
      expect(notifier.pending!.body, contains('Lecture'));
    });

    test('...unless forced, or nothing was scheduled', () async {
      await scheduler.reschedule(
        config: config,
        source: _Failing(),
        zone: paris,
      );
      expect(notifier.pending!.title, endsWith('calendar unavailable'));
      await scheduler.reschedule(config: config, source: source, zone: paris);
      await scheduler.reschedule(
        config: config,
        source: _Failing(),
        zone: paris,
        force: true,
      );
      expect(notifier.scheduled, hasLength(3));
      expect(notifier.pending!.title, endsWith('calendar unavailable'));
    });

    test('no source yet: the brief says the calendar is unavailable', () async {
      await scheduler.reschedule(config: config, source: null, zone: paris);
      expect(notifier.pending!.title, endsWith('calendar unavailable'));
    });
  });

  group('in the app', () {
    late MemoryFolderAccess access;
    late FakeBriefNotifier notifier;
    late AppServices services;

    Future<void> start(
      WidgetTester tester, {
      SourcePlatform platform = SourcePlatform.android,
      bool withNotifier = true,
    }) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      access = MemoryFolderAccess();
      final clock = FakeClock(p(9, 6));
      await SasaFolder(access.folder(syncA.ref))
          .saveConfig(AppConfig.defaults(clock: clock));
      notifier = FakeBriefNotifier(allowed: false);
      services = testServices(
        platform: platform,
        settings: MemoryDeviceSettings(
          syncFolder: syncA,
          setupDone: true,
          forceCalDav: true,
        ),
        access: access,
        calDav: FakeSource(events: [ev('Lecture', p(9, 14), p(9, 16))]),
        clock: clock,
        briefNotifier: withNotifier ? notifier : null,
      );
      await notifier.init(onOpenToday: services.openToday);
      await tester.pumpWidget(SasaApp(services: services));
      await tester.pumpAndSettle();
    }

    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('on start: asks for notifications and schedules', (
      tester,
    ) async {
      await start(tester);
      expect(notifier.permissionRequests, 1);
      expect(notifier.scheduled, hasLength(1));
      expect(notifier.pending!.body, contains('Lecture'));
    });

    testWidgets('coming back to the foreground re-renders', (tester) async {
      await start(tester);
      await services.resumed();
      expect(notifier.scheduled, hasLength(2));
    });

    testWidgets('settings change the brief for every device and reschedule', (
      tester,
    ) async {
      await start(tester);
      await openSettings(tester);
      expect(find.text('Morning brief'), findsWidgets);
      expect(find.text('07:30 (Europe/Paris)'), findsOneWidget);
      expect(find.text('Next: Mon 9 Nov 07:30'), findsOneWidget);

      await tester.tap(find.text('Every day'));
      await tester.pumpAndSettle();
      final saved = (await SasaFolder(access.folder(syncA.ref)).loadConfig())!;
      expect(saved.brief.days, BriefDays.everyDay);
      expect(notifier.scheduled, hasLength(2));

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(
        (await SasaFolder(
          access.folder(syncA.ref),
        ).loadConfig())!.brief.enabled,
        isFalse,
      );
      expect(notifier.pending, isNull, reason: 'cancelled');
    });

    testWidgets('the time picker sets the brief time', (tester) async {
      await start(tester);
      await openSettings(tester);
      await tester.tap(find.text('Time'));
      await tester.pumpAndSettle();
      // Switch the dial to text input and type 08:15.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '08');
      await tester.enterText(fields.at(1), '15');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final saved = (await SasaFolder(access.folder(syncA.ref)).loadConfig())!;
      expect(saved.brief.time, const LocalTime(8, 15));
      expect(notifier.pending!.at.hour, 8);
      expect(notifier.pending!.at.minute, 15);
    });

    testWidgets('missing permissions show what to allow', (tester) async {
      await start(tester);
      notifier
        ..grantOnRequest = false
        ..allowed = false;
      await services.brief!.refresh();
      await openSettings(tester);
      expect(find.text('Notifications are off for Sasa'), findsOneWidget);

      notifier
        ..allowed = true
        ..exact = false;
      await services.brief!.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Exact alarms not allowed'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Allow'));
      await tester.pumpAndSettle();
      expect(notifier.exactRequests, 1);
      expect(find.text('Exact alarms not allowed'), findsNothing);
    });

    testWidgets('tapping the brief returns to Today', (tester) async {
      await start(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Rules'),
        ),
      );
      await openSettings(tester);
      notifier.onOpenToday!();
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsNothing);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Today')),
        findsOneWidget,
      );
    });

    testWidgets('on Linux, settings point to the sasa timers', (tester) async {
      await start(tester, platform: SourcePlatform.linux, withNotifier: false);
      await openSettings(tester);
      expect(find.text('On this computer'), findsOneWidget);
      expect(find.textContaining('Next:'), findsNothing);
      expect(services.brief, isNull);
    });
  });
}
