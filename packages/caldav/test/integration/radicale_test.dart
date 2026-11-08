@Tags(['integration'])
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sasa_caldav/sasa_caldav.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Only ever the disposable server from tools/radicale-test.
final Uri radicale = Uri.parse(
  Platform.environment['SASA_RADICALE_URL'] ??
      'http://127.0.0.1:${Platform.environment['SASA_RADICALE_PORT'] ?? '5232'}/',
);

void main() {
  late http.Client httpClient;
  late CalDavSource source;

  setUp(() {
    httpClient = http.Client();
    source = CalDavSource(
      client: CalDavClient(
        baseUri: radicale,
        httpClient: httpClient,
        credentials: const CalDavCredentials('test', 'test'),
      ),
      zones: parisZones(),
    );
  });

  tearDown(() => httpClient.close());

  test('discovers the seeded calendar and task list', () async {
    final cols = await source.collections();
    final byName = {for (final c in cols) c.displayName: c};
    expect(byName.keys, containsAll(['Sasa test calendar', 'Sasa test tasks']));
    expect(byName['Sasa test calendar']!.components, {'VEVENT'});
    expect(byName['Sasa test tasks']!.components, {'VTODO'});
    expect(byName['Sasa test calendar']!.uri.path, '/test/sasa-calendar/');
  });

  test('events of the seeded week', () async {
    final events = await source.events(p(2026, 11, 2), p(2026, 11, 9));
    expect(
      [for (final e in events) (e.title, e.start, e.end, e.busy)],
      [
        ('Networks lab', p(2026, 11, 2, 10, 30), p(2026, 11, 2, 12, 30), true),
        (
          'Meeting with supervisor',
          p(2026, 11, 2, 14),
          p(2026, 11, 2, 15),
          true,
        ),
        (
          'Lab seminar (optional)',
          p(2026, 11, 3, 16),
          p(2026, 11, 3, 17),
          false,
        ),
        ('Call with collaborators', z(2026, 11, 4, 8), z(2026, 11, 4, 9), true),
        (
          'Open day (info only)',
          DateTime.utc(2026, 11, 5),
          DateTime.utc(2026, 11, 6),
          false,
        ),
        (
          'Thesis committee day',
          DateTime.utc(2026, 11, 6),
          DateTime.utc(2026, 11, 7),
          true,
        ),
      ],
    );
  });

  test('weekly lab across DST, EXDATE and moved override', () async {
    final lab = [
      for (final e in await source.events(p(2026, 10, 19), p(2026, 11, 23)))
        if (e.uid == 'sasa-seed-lab-networks') (e.title, e.start),
    ];
    expect(lab, [
      ('Networks lab', z(2026, 10, 19, 8, 30)),
      ('Networks lab', z(2026, 10, 26, 9, 30)),
      ('Networks lab', z(2026, 11, 2, 9, 30)),
      ('Networks lab (moved)', p(2026, 11, 16, 14)),
    ]);
  });

  test('moved instance is not reported in its original slot', () async {
    // Radicale's own `expand` gets this wrong; we expand on the client.
    final events = await source.events(
      p(2026, 11, 16, 10, 30),
      p(2026, 11, 16, 11),
    );
    expect(events, isEmpty);
  });

  test('open tasks', () async {
    final tasks = await source.openTasks();
    expect(tasks.map((t) => t.uid).toSet(), {
      'sasa-seed-prepare-lab-sockets',
      'sasa-seed-read-openalex-docs',
      'sasa-seed-review-paper',
    });
    final review = tasks.singleWhere((t) => t.uid == 'sasa-seed-review-paper');
    expect(review.priority, 1);
    expect(review.tags, ['review', 'research']);
    expect(review.due, p(2026, 11, 3, 18));
  });

  test('all tasks include the completed one', () async {
    final tasks = await source.tasks();
    expect(tasks, hasLength(4));
    expect(
      tasks.singleWhere((t) => t.uid == 'sasa-seed-expense-report').completed,
      isTrue,
    );
  });

  test('wrong password is rejected', () async {
    final bad = CalDavClient(
      baseUri: radicale,
      httpClient: httpClient,
      credentials: const CalDavCredentials('test', 'wrong'),
    );
    await expectLater(
      bad.discoverPrincipal(),
      throwsA(isA<CalDavAuthException>()),
    );
  });
}
