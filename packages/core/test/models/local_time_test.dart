import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

void main() {
  group('LocalTime', () {
    test('parses and formats HH:mm', () {
      final t = LocalTime.parse('09:05');
      expect(t.hour, 9);
      expect(t.minute, 5);
      expect(t.minutesSinceMidnight, 545);
      expect(t.toString(), '09:05');
    });

    test('accepts 24:00 as end of day', () {
      expect(LocalTime.parse('24:00').minutesSinceMidnight, 1440);
    });

    for (final bad in ['9:00', '24:01', '12:60', 'noon', '', '-1:00']) {
      test('rejects "$bad"', () {
        expect(() => LocalTime.parse(bad), throwsFormatException);
      });
    }

    test('compares and has value equality', () {
      expect(LocalTime.parse('08:00'), const LocalTime(8, 0));
      expect(
        const LocalTime(8, 0).compareTo(const LocalTime(9, 0)),
        lessThan(0),
      );
    });
  });

  group('TimeWindow', () {
    test('round-trips JSON', () {
      final win = TimeWindow(const LocalTime(9, 0), const LocalTime(12, 0));
      expect(win.toJson(), {'start': '09:00', 'end': '12:00'});
      expect(TimeWindow.fromJson(win.toJson()), win);
    });

    test('rejects end not after start', () {
      expect(
        () => TimeWindow.fromJson({'start': '12:00', 'end': '12:00'}),
        throwsFormatException,
      );
      expect(
        () => TimeWindow(const LocalTime(12, 0), const LocalTime(9, 0)),
        throwsArgumentError,
      );
    });

    test('contains is start-inclusive, end-exclusive', () {
      final win = TimeWindow(const LocalTime(9, 0), const LocalTime(12, 0));
      expect(win.contains(const LocalTime(9, 0)), isTrue);
      expect(win.contains(const LocalTime(11, 59)), isTrue);
      expect(win.contains(const LocalTime(12, 0)), isFalse);
      expect(win.contains(const LocalTime(8, 59)), isFalse);
    });
  });
}
