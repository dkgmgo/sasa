import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('formatClock shows local wall-clock time', () {
    expect(formatClock(p(2026, 11, 9, 9, 5), paris), '09:05');
    expect(formatClock(z(2026, 7, 1, 22), paris), '00:00');
  });

  test('formatMinutes', () {
    expect(formatMinutes(0), '0 min');
    expect(formatMinutes(45), '45 min');
    expect(formatMinutes(60), '1 h');
    expect(formatMinutes(90), '1 h 30');
    expect(formatMinutes(125), '2 h 05');
    expect(formatMinutes(15 * 60), '15 h');
  });

  test('formatDate and formatShortDate', () {
    expect(formatDate(DateTime.utc(2026, 11, 9)), 'Monday 9 November');
    expect(formatShortDate(DateTime.utc(2026, 11, 15)), 'Sun 15 Nov');
  });

  group('formatDue', () {
    final now = p(2026, 11, 9, 10);
    String due(DateTime d) => formatDue(d, now: now, zone: paris);

    test('today and tomorrow with a time', () {
      expect(due(p(2026, 11, 9, 18)), 'Today 18:00');
      expect(due(p(2026, 11, 10, 9, 30)), 'Tomorrow 09:30');
    });

    test('date-only due dates (end of day) show no time', () {
      expect(due(endOfLocalDate(DateTime(2026, 11, 9), paris)), 'Today');
      expect(due(endOfLocalDate(DateTime(2026, 11, 11), paris)), 'Wed 11 Nov');
    });

    test('overdue', () {
      expect(due(p(2026, 11, 9, 8)), 'Overdue · Today 08:00');
      expect(
        due(endOfLocalDate(DateTime(2026, 11, 6), paris)),
        'Overdue · Fri 6 Nov',
      );
    });
  });

  test('formatTimeRange', () {
    expect(
      formatTimeRange(p(2026, 11, 9, 9), p(2026, 11, 9, 10, 30), paris),
      '09:00–10:30',
    );
  });

  test('describeMatch for every field', () {
    MappingRule r(MatchField f, String p) =>
        MappingRule(field: f, pattern: p, categoryId: 'x');
    expect(
      describeMatch(r(MatchField.calendar, 'Cours')),
      'Calendar is “Cours”',
    );
    expect(describeMatch(r(MatchField.list, 'PhD')), 'List is “PhD”');
    expect(describeMatch(r(MatchField.tag, 'read')), 'Tag is “read”');
    expect(
      describeMatch(r(MatchField.titleRegex, 'seminar')),
      'Title matches /seminar/',
    );
  });

  test('energyLabel', () {
    expect(Energy.values.map(energyLabel), ['Low', 'Medium', 'High']);
  });

  test('matchFieldLabel', () {
    expect(MatchField.values.map(matchFieldLabel), [
      'Calendar',
      'Task list',
      'Task tag',
      'Title (regular expression)',
    ]);
  });

  test('describeCategory', () {
    final byId = {for (final c in defaultCategories()) c.id: c};
    expect(
      describeCategory(byId['research']!),
      '15 h a week · 1 h 30 blocks · high energy · best 09:00–12:00',
    );
    expect(
      describeCategory(byId['teaching']!),
      'No weekly target · 1 h blocks · medium energy',
    );
  });

  test('describeBrief', () {
    final b = BriefSettings.defaults();
    expect(describeBrief(b), '07:30 on weekdays');
    expect(
      describeBrief(b.copyWith(days: BriefDays.everyDay)),
      '07:30 every day',
    );
    expect(describeBrief(b.copyWith(enabled: false)), 'Off');
  });
}
