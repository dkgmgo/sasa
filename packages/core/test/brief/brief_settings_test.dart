import 'dart:convert';

import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final weekdays = BriefSettings(time: const LocalTime(7, 30));
  final everyDay = BriefSettings(
    time: const LocalTime(7, 30),
    days: BriefDays.everyDay,
  );

  group('BriefSettings', () {
    test('defaults: on, 07:30, weekdays', () {
      final d = BriefSettings.defaults();
      expect(d.enabled, isTrue);
      expect(d.time, const LocalTime(7, 30));
      expect(d.days, BriefDays.weekdays);
    });

    test('weekdays only means Monday to Friday', () {
      expect(
        [for (var d = 1; d <= 7; d++) weekdays.occursOn(d)],
        [true, true, true, true, true, false, false],
      );
      expect([
        for (var d = 1; d <= 7; d++) everyDay.occursOn(d),
      ], everyElement(isTrue));
    });

    test('a disabled brief occurs on no day', () {
      final off = weekdays.copyWith(enabled: false);
      expect([
        for (var d = 1; d <= 7; d++) off.occursOn(d),
      ], everyElement(isFalse));
    });

    test('24:00 is not a brief time', () {
      expect(
        () => BriefSettings(time: const LocalTime(24, 0)),
        throwsArgumentError,
      );
      expect(
        () => BriefSettings.fromJson({
          'enabled': true,
          'time': '24:00',
          'days': 'weekdays',
        }),
        throwsFormatException,
      );
    });

    test('round-trips through JSON', () {
      final s = everyDay.copyWith(enabled: false, time: const LocalTime(6, 5));
      final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>;
      expect(json, {'enabled': false, 'time': '06:05', 'days': 'everyDay'});
      expect(BriefSettings.fromJson(json), s);
    });

    test('unknown days value is a format error', () {
      expect(
        () => BriefSettings.fromJson({
          'enabled': true,
          'time': '07:30',
          'days': 'sometimes',
        }),
        throwsFormatException,
      );
    });
  });

  group('AppConfig.brief', () {
    final config = AppConfig.defaults(clock: FakeClock(z(2026, 11, 1)));

    test('defaults to BriefSettings.defaults()', () {
      expect(config.brief, BriefSettings.defaults());
    });

    test('is saved and read back', () {
      final c = config.copyWith(brief: everyDay);
      final json = jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>;
      expect(AppConfig.fromJson(json).brief, everyDay);
      expect(AppConfig.fromJson(json), c);
    });

    test('is optional, for files written before it existed', () {
      final json =
          jsonDecode(jsonEncode(config.toJson())) as Map<String, Object?>
            ..remove('brief');
      expect(AppConfig.fromJson(json).brief, BriefSettings.defaults());
    });

    test('ConfigEdits.setBrief replaces it', () {
      final edited = ConfigEdits.setBrief(everyDay)(config);
      expect(edited.brief, everyDay);
      expect(edited.categories, config.categories);
    });
  });
}
