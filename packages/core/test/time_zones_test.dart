import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('endOfLocalDate', () {
    test('last second of the date in the zone (winter, UTC+1)', () {
      expect(
        endOfLocalDate(DateTime.utc(2026, 11, 9), paris),
        DateTime.utc(2026, 11, 9, 22, 59, 59),
      );
    });

    test('summer time (UTC+2)', () {
      expect(
        endOfLocalDate(DateTime.utc(2026, 7, 1), paris),
        DateTime.utc(2026, 7, 1, 21, 59, 59),
      );
    });

    test('DST change days in Europe/Paris', () {
      // 25 Oct 2026: clocks go back; the day ends at 23:00Z (UTC+1).
      expect(
        endOfLocalDate(DateTime.utc(2026, 10, 25), paris),
        DateTime.utc(2026, 10, 25, 22, 59, 59),
      );
      // 29 Mar 2026: clocks go forward; the day ends at 22:00Z (UTC+2).
      expect(
        endOfLocalDate(DateTime.utc(2026, 3, 29), paris),
        DateTime.utc(2026, 3, 29, 21, 59, 59),
      );
    });

    test('ignores the time part of the input', () {
      expect(
        endOfLocalDate(DateTime.utc(2026, 11, 9, 17, 30), paris),
        endOfLocalDate(DateTime.utc(2026, 11, 9), paris),
      );
    });
  });

  test('locationOrDefault falls back to the default zone', () {
    expect(locationOrDefault('Africa/Nairobi').name, 'Africa/Nairobi');
    expect(locationOrDefault('Mars/Olympus').name, defaultTimeZone);
  });
}
