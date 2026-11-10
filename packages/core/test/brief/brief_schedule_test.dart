import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final weekdays = BriefSettings(time: const LocalTime(7, 30));
  final everyDay = weekdays.copyWith(days: BriefDays.everyDay);

  group('nextBriefAt', () {
    test('later today when the time has not passed yet', () {
      // Monday 9 Nov 2026.
      expect(
        nextBriefAt(weekdays, after: p(2026, 11, 9, 6), zone: paris),
        p(2026, 11, 9, 7, 30),
      );
    });

    test('tomorrow once today\'s brief time has passed', () {
      expect(
        nextBriefAt(weekdays, after: p(2026, 11, 9, 7, 30), zone: paris),
        p(2026, 11, 10, 7, 30),
      );
      expect(
        nextBriefAt(weekdays, after: p(2026, 11, 9, 23, 59), zone: paris),
        p(2026, 11, 10, 7, 30),
      );
    });

    test('weekdays only skips the weekend', () {
      // Friday 13 Nov after the brief → Monday 16 Nov.
      expect(
        nextBriefAt(weekdays, after: p(2026, 11, 13, 8), zone: paris),
        p(2026, 11, 16, 7, 30),
      );
      // Saturday → Monday.
      expect(
        nextBriefAt(weekdays, after: p(2026, 11, 14, 6), zone: paris),
        p(2026, 11, 16, 7, 30),
      );
    });

    test('every day includes the weekend', () {
      expect(
        nextBriefAt(everyDay, after: p(2026, 11, 13, 8), zone: paris),
        p(2026, 11, 14, 7, 30),
      );
    });

    test('null when the brief is off', () {
      expect(
        nextBriefAt(
          weekdays.copyWith(enabled: false),
          after: p(2026, 11, 9, 6),
          zone: paris,
        ),
        isNull,
      );
    });

    test('keeps the wall-clock time across a DST change', () {
      // Paris leaves summer time on Sunday 25 Oct 2026.
      final sat = nextBriefAt(everyDay, after: p(2026, 10, 23, 8), zone: paris);
      final sun = nextBriefAt(everyDay, after: sat!, zone: paris);
      final mon = nextBriefAt(everyDay, after: sun!, zone: paris);
      expect(sat, z(2026, 10, 24, 5, 30)); // 07:30 CEST
      expect(sun, z(2026, 10, 25, 6, 30)); // 07:30 CET
      expect(mon, z(2026, 10, 26, 6, 30));
    });

    test('a time in the spring-forward gap moves to just after it', () {
      // 02:30 does not exist in Paris on Sunday 29 March 2026.
      final s = everyDay.copyWith(time: const LocalTime(2, 30));
      final at = nextBriefAt(s, after: p(2026, 3, 28, 12), zone: paris)!;
      expect(at, z(2026, 3, 29, 1, 30)); // 03:30 CEST
      expect(
        nextBriefAt(s, after: at, zone: paris),
        z(2026, 3, 30, 0, 30), // 02:30 CEST
      );
    });

    test('uses the configured zone, not UTC dates', () {
      // 23:30 UTC on Sunday is already Monday 00:30 in Paris.
      expect(
        nextBriefAt(weekdays, after: z(2026, 11, 8, 23, 30), zone: paris),
        p(2026, 11, 9, 7, 30),
      );
    });
  });

  group('scheduledBriefDue', () {
    test('due from the brief time until the late limit', () {
      bool due(int h, int m) =>
          scheduledBriefDue(weekdays, now: p(2026, 11, 9, h, m), zone: paris);
      expect(due(7, 29), isFalse);
      expect(due(7, 30), isTrue);
      expect(due(10, 29), isTrue);
      expect(due(10, 30), isFalse); // 3 h late: too stale to send
    });

    test('never on a day without a brief, or when off', () {
      expect(
        scheduledBriefDue(weekdays, now: p(2026, 11, 14, 8), zone: paris),
        isFalse,
      );
      expect(
        scheduledBriefDue(
          weekdays.copyWith(enabled: false),
          now: p(2026, 11, 9, 8),
          zone: paris,
        ),
        isFalse,
      );
    });

    test('the late limit can be changed', () {
      expect(
        scheduledBriefDue(
          weekdays,
          now: p(2026, 11, 9, 12),
          zone: paris,
          lateLimit: const Duration(hours: 6),
        ),
        isTrue,
      );
    });
  });
}
