import 'package:http/http.dart' as http;
import 'package:sasa_caldav/sasa_caldav.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'fake_dav.dart';
import 'helpers.dart';

CalDavSource sourceFor(FakeDav dav, {ParseErrorHandler? onParseError}) =>
    CalDavSource(
      client: CalDavClient(
        baseUri: Uri.parse('http://dav.test:5232/'),
        httpClient: dav.client,
        credentials: const CalDavCredentials('test', 'test'),
      ),
      zones: parisZones(),
      onParseError: onParseError,
    );

void main() {
  test('is a CalendarSource', () {
    expect(sourceFor(FakeDav()), isA<CalendarSource>());
  });

  test('events of the seeded week, expanded and sorted', () async {
    final events = await sourceFor(FakeDav())
        .events(p(2026, 11, 2), p(2026, 11, 9));
    expect(
      [for (final e in events) (e.title, e.start, e.busy)],
      [
        ('Networks lab', p(2026, 11, 2, 10, 30), true),
        ('Meeting with supervisor', p(2026, 11, 2, 14), true),
        ('Lab seminar (optional)', p(2026, 11, 3, 16), false),
        ('Call with collaborators', z(2026, 11, 4, 8), true),
        ('Open day (info only)', DateTime.utc(2026, 11, 5), false),
        ('Thesis committee day', DateTime.utc(2026, 11, 6), true),
      ],
    );
    expect(events.every((e) => e.calendarName == 'Sasa test calendar'), isTrue);
    expect(events[4].allDay, isTrue);
  });

  test('server range is widened by a day, results are exact', () async {
    final dav = FakeDav();
    final events = await sourceFor(dav).events(p(2026, 11, 4), p(2026, 11, 5));
    expect(dav.seen.last.body, contains('start="20261102T230000Z"'));
    expect(dav.seen.last.body, contains('end="20261105T230000Z"'));
    expect([for (final e in events) e.title], ['Call with collaborators']);
  });

  test('collections are discovered once and cached', () async {
    final dav = FakeDav();
    final src = sourceFor(dav);
    await src.events(p(2026, 11, 2), p(2026, 11, 9));
    await src.events(p(2026, 11, 2), p(2026, 11, 9));
    expect(dav.seen.where((s) => s.method == 'PROPFIND'), hasLength(4));
    await src.refreshCollections();
    expect(dav.seen.where((s) => s.method == 'PROPFIND'), hasLength(8));
  });

  test('openTasks: completed ones filtered', () async {
    final tasks = await sourceFor(FakeDav()).openTasks();
    expect(tasks.map((t) => t.uid).toSet(), {
      'sasa-seed-prepare-lab-sockets',
      'sasa-seed-read-openalex-docs',
      'sasa-seed-review-paper',
    });
    expect(tasks.every((t) => t.listName == 'Sasa test tasks'), isTrue);
  });

  test(
    'openTasks also drops STATUS:COMPLETED without COMPLETED date',
    () async {
      final routes = radicaleRoutes();
      routes['REPORT /test/sasa-tasks/'] = (_) => multistatus(
        _objects({
          '/test/sasa-tasks/a.ics': vcal(
            'BEGIN:VTODO\nUID:a\nSTATUS:COMPLETED\nEND:VTODO',
          ),
          '/test/sasa-tasks/b.ics': vcal('BEGIN:VTODO\nUID:b\nEND:VTODO'),
        }),
      );
      final tasks = await sourceFor(FakeDav(routes: routes)).openTasks();
      expect(tasks.map((t) => t.uid), ['b']);
    },
  );

  test('tasks(): all tasks including completed', () async {
    final tasks = await sourceFor(FakeDav()).tasks();
    expect(tasks, hasLength(4));
    expect(
      tasks.singleWhere((t) => t.uid == 'sasa-seed-expense-report').completed,
      isTrue,
    );
  });

  test('a broken resource is reported and skipped', () async {
    final routes = radicaleRoutes();
    routes['REPORT /test/sasa-calendar/'] = (_) => multistatus(
      _objects({
        '/test/sasa-calendar/bad.ics': 'BEGIN:VCALENDAR\nBEGIN:VEVENT\n',
        '/test/sasa-calendar/ok.ics': vcal(
          'BEGIN:VEVENT\nUID:ok\nDTSTART:20261102T090000Z\nEND:VEVENT',
        ),
      }),
    );
    final errors = <Uri>[];
    final events = await sourceFor(
      FakeDav(routes: routes),
      onParseError: (uri, _) => errors.add(uri),
    ).events(z(2026, 11, 2), z(2026, 11, 3));
    expect(events.map((e) => e.uid), ['ok']);
    expect(errors.single.path, '/test/sasa-calendar/bad.ics');
  });

  test('auth failure surfaces as CalDavAuthException', () async {
    final dav = FakeDav(
      routes: {'PROPFIND /.well-known/caldav': (_) => http.Response('', 401)},
    );
    await expectLater(
      sourceFor(dav).events(z(2026, 1, 1), z(2027, 1, 1)),
      throwsA(isA<CalDavAuthException>()),
    );
  });
}

String _objects(Map<String, String> byHref) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return '<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
      '${byHref.entries.map((e) => '<response><href>${e.key}</href><propstat>'
          '<prop><C:calendar-data>${esc(e.value)}</C:calendar-data></prop>'
          '<status>HTTP/1.1 200 OK</status></propstat></response>').join()}'
      '</multistatus>';
}
