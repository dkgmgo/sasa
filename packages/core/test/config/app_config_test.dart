import 'dart:convert';

import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

void main() {
  final clock = FakeClock(DateTime.utc(2026, 11, 8, 12));
  final config = AppConfig.defaults(clock: clock);

  Map<String, Object?> encodeDecode(AppConfig c) =>
      jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>;

  group('defaults', () {
    test('six default categories in order', () {
      expect(config.categories.map((c) => c.name), [
        'Reading',
        'Research',
        'Writing/Blog',
        'News/Veille',
        'Teaching',
        'Admin',
      ]);
      expect(config.categories.map((c) => c.id).toSet(), hasLength(6));
    });

    test('updatedAt comes from the clock, version is current', () {
      expect(config.updatedAt, DateTime.utc(2026, 11, 8, 12));
      expect(config.version, AppConfig.currentVersion);
      expect(AppConfig.currentVersion, 1);
    });

    test('free-block settings, time zone and weights', () {
      expect(config.timeZone, 'Europe/Paris');
      expect(config.freeBlocks, FreeBlockSettings.defaults());
      expect(config.weights.urgency, 0.30);
      expect(config.weights.neglect, 0.25);
      expect(config.weights.fit, 0.20);
      expect(config.weights.timeOfDay, 0.15);
      expect(config.weights.energyMatch, 0.10);
      expect(config.weights.skipPenalty, 0.30);
    });

    test('no rules or nudges until the user creates them', () {
      expect(config.rules, isEmpty);
      expect(config.nudges, isEmpty);
    });

    test('default time zone resolves', () {
      expect(locationFor(config.timeZone).name, 'Europe/Paris');
    });

    test('categoryById', () {
      expect(config.categoryById('teaching')?.name, 'Teaching');
      expect(config.categoryById('nope'), isNull);
    });
  });

  group('JSON', () {
    final full = config.copyWith(
      rules: const [
        MappingRule(
          field: MatchField.calendar,
          pattern: 'Cours',
          categoryId: 'teaching',
          priority: 5,
        ),
      ],
      nudges: [
        Nudge(
          id: 'blog',
          title: 'Write a blog post',
          categoryId: 'writing',
          schedule: Schedule(
            weekdays: const {DateTime.sunday},
            period: SchedulePeriod.week,
          ),
          window: TimeWindow(const LocalTime(14, 0), const LocalTime(18, 0)),
          minMinutes: 45,
          durationMin: 60,
        ),
      ],
      inboxIgnored: const [InboxIgnore(field: MatchField.list, name: 'To Buy')],
    );

    test('round-trips through a JSON string', () {
      expect(AppConfig.fromJson(encodeDecode(config)), config);
      expect(AppConfig.fromJson(encodeDecode(full)), full);
    });

    test('carries version and UTC updatedAt', () {
      final json = config.toJson();
      expect(json['version'], 1);
      expect(json['updatedAt'], '2026-11-08T12:00:00.000Z');
    });

    test('weights decode from integer JSON numbers', () {
      final json = encodeDecode(config);
      (json['weights']! as Map<String, Object?>)['urgency'] = 1;
      expect(AppConfig.fromJson(json).weights.urgency, 1.0);
    });

    test('inboxIgnored is optional, for files written before it existed', () {
      final json = encodeDecode(full)..remove('inboxIgnored');
      expect(AppConfig.fromJson(json).inboxIgnored, isEmpty);
      expect(config.inboxIgnored, isEmpty);
    });

    test('an inboxIgnored entry must be a calendar or a list', () {
      final json = encodeDecode(full)
        ..['inboxIgnored'] = [
          {'field': 'tag', 'name': 'x'},
        ];
      expect(() => AppConfig.fromJson(json), throwsFormatException);
    });

    test('unknown keys are ignored', () {
      final json = encodeDecode(config)..['futureThing'] = 42;
      expect(AppConfig.fromJson(json), config);
    });

    test('newer version is refused', () {
      final json = encodeDecode(config)..['version'] = 2;
      expect(
        () => AppConfig.fromJson(json),
        throwsA(
          isA<UnsupportedConfigVersion>()
              .having((e) => e.found, 'found', 2)
              .having((e) => e.supported, 'supported', 1),
        ),
      );
    });

    test('missing or invalid version is a format error', () {
      expect(
        () => AppConfig.fromJson(encodeDecode(config)..remove('version')),
        throwsFormatException,
      );
      expect(
        () => AppConfig.fromJson(encodeDecode(config)..['version'] = 0),
        throwsFormatException,
      );
    });

    test('missing section is a format error', () {
      expect(
        () => AppConfig.fromJson(encodeDecode(config)..remove('categories')),
        throwsFormatException,
      );
    });

    test('duplicate category ids are rejected', () {
      final json = encodeDecode(config);
      final cats = json['categories']! as List<Object?>;
      json['categories'] = [...cats, cats.first];
      expect(() => AppConfig.fromJson(json), throwsFormatException);
    });
  });

  test('copyWith keeps other fields and lists are unmodifiable', () {
    final later = config.copyWith(updatedAt: DateTime.utc(2026, 12));
    expect(later.updatedAt, DateTime.utc(2026, 12));
    expect(later.categories, config.categories);
    expect(
      () => later.categories.add(config.categories.first),
      throwsUnsupportedError,
    );
  });
}
