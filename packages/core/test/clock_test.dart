import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

void main() {
  group('FakeClock', () {
    test('returns the set instant in UTC', () {
      final clock = FakeClock(DateTime.utc(2026, 11, 9, 7, 30));
      expect(clock.now(), DateTime.utc(2026, 11, 9, 7, 30));
      expect(clock.now().isUtc, isTrue);
    });

    test('normalises a non-UTC start to UTC', () {
      final clock = FakeClock(DateTime.parse('2026-11-09T08:30:00+01:00'));
      expect(clock.now(), DateTime.utc(2026, 11, 9, 7, 30));
      expect(clock.now().isUtc, isTrue);
    });

    test('advance and set move time', () {
      final clock = FakeClock(DateTime.utc(2026, 11, 9));
      clock.advance(const Duration(minutes: 90));
      expect(clock.now(), DateTime.utc(2026, 11, 9, 1, 30));
      clock.set(DateTime.utc(2027));
      expect(clock.now(), DateTime.utc(2027));
    });
  });

  test('FunctionClock delegates and normalises to UTC', () {
    final clock = FunctionClock(
      () => DateTime.parse('2026-03-29T03:00:00+02:00'),
    );
    expect(clock.now(), DateTime.utc(2026, 3, 29, 1));
    expect(clock.now().isUtc, isTrue);
  });
}
