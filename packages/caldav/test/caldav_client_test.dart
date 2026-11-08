import 'package:http/http.dart' as http;
import 'package:sasa_caldav/sasa_caldav.dart';
import 'package:test/test.dart';

import 'fake_dav.dart';
import 'helpers.dart';

final base = Uri.parse('http://dav.test:5232/');
const creds = CalDavCredentials('test', 'secret-pw');

CalDavClient clientFor(FakeDav dav, {Uri? baseUri}) => CalDavClient(
  baseUri: baseUri ?? base,
  httpClient: dav.client,
  credentials: creds,
);

void main() {
  group('discovery', () {
    test(
      'well-known relative redirect -> principal -> home -> collections',
      () async {
        final dav = FakeDav();
        final cols = await clientFor(dav).discoverCollections();

        expect(dav.seen.map((s) => '${s.method} ${s.uri.path}'), [
          'PROPFIND /.well-known/caldav',
          'PROPFIND /',
          'PROPFIND /test/',
          'PROPFIND /test/',
        ]);
        expect(cols.map((c) => c.displayName), [
          'Sasa test calendar',
          'Sasa test tasks',
        ]);
        final cal = cols.first;
        expect(cal.uri, Uri.parse('http://dav.test:5232/test/sasa-calendar/'));
        expect(cal.components, {'VEVENT'});
        expect(cal.hasEvents, isTrue);
        expect(cal.hasTasks, isFalse);
        expect(cal.ctag, startsWith('"6a72'));
        expect(cols.last.components, {'VTODO'});
      },
    );

    test('sends Depth, XML content type and Basic auth', () async {
      final dav = FakeDav();
      await clientFor(dav).discoverPrincipal();
      final first = dav.seen.first;
      expect(first.headers['Depth'], '0');
      expect(first.headers['Content-Type'], startsWith('application/xml'));
      expect(first.headers['Authorization'], 'Basic dGVzdDpzZWNyZXQtcHc=');
      expect(first.body, contains('current-user-principal'));
    });

    test('base URL with a path is tried before well-known', () async {
      final dav = FakeDav(
        routes: {
          'PROPFIND /radicale/': (_) => multistatus(
            '<multistatus xmlns="DAV:"><response><href>/radicale/</href>'
            '<propstat><prop><current-user-principal>'
            '<href>/radicale/me/</href></current-user-principal></prop>'
            '<status>HTTP/1.1 200 OK</status></propstat></response>'
            '</multistatus>',
          ),
        },
      );
      final principal = await clientFor(
        dav,
        baseUri: Uri.parse('https://dav.test/radicale/'),
      ).discoverPrincipal();
      expect(principal, Uri.parse('https://dav.test/radicale/me/'));
      expect(dav.seen, hasLength(1));
    });

    test('falls back to the base URL when well-known is missing', () async {
      final routes = radicaleRoutes()..remove('PROPFIND /.well-known/caldav');
      final dav = FakeDav(routes: routes);
      expect(
        await clientFor(dav).discoverPrincipal(),
        Uri.parse('http://dav.test:5232/test/'),
      );
    });

    test(
      '401 throws CalDavAuthException without leaking the password',
      () async {
        final dav = FakeDav(
          routes: {
            'PROPFIND /.well-known/caldav': (_) => http.Response('no', 401),
          },
        );
        final err = await clientFor(dav)
            .discoverPrincipal()
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect(err, isA<CalDavAuthException>());
        expect(err.toString(), isNot(contains('secret-pw')));
        expect(creds.toString(), isNot(contains('secret-pw')));
      },
    );

    test('no principal anywhere throws CalDavException', () async {
      final dav = FakeDav(routes: {});
      expect(
        clientFor(dav).discoverPrincipal(),
        throwsA(isA<CalDavException>()),
      );
    });

    test('credentials are not sent after a cross-origin redirect', () async {
      final dav = FakeDav(
        routes: {
          'PROPFIND /.well-known/caldav': (_) => http.Response(
            '',
            301,
            headers: {'location': 'https://elsewhere.test/'},
          ),
          'PROPFIND /': (_) =>
              multistatus(fixture('radicale/propfind-principal.xml')),
        },
      );
      await clientFor(dav).discoverPrincipal();
      expect(dav.seen.last.uri.host, 'elsewhere.test');
      expect(dav.seen.last.headers.containsKey('Authorization'), isFalse);
    });

    test('redirect loop stops', () async {
      final dav = FakeDav(
        routes: {
          'PROPFIND /.well-known/caldav': (_) => http.Response(
            '',
            302,
            headers: {'location': '/.well-known/caldav'},
          ),
        },
      );
      await expectLater(
        clientFor(dav).discoverPrincipal(),
        throwsA(isA<CalDavException>()),
      );
    });

    test('collection without component set or display name', () async {
      final dav = FakeDav(
        routes: {
          'PROPFIND /home/': (_) => multistatus(
            '<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
            '<response><href>/home/work/</href><propstat><prop>'
            '<resourcetype><collection/><C:calendar/></resourcetype>'
            '</prop><status>HTTP/1.1 200 OK</status></propstat></response>'
            '<response><href>/home/addressbook/</href><propstat><prop>'
            '<resourcetype><collection/></resourcetype>'
            '</prop><status>HTTP/1.1 200 OK</status></propstat></response>'
            '</multistatus>',
          ),
        },
      );
      final cols = await clientFor(dav)
          .listCollections(Uri.parse('http://dav.test:5232/home/'));
      expect(cols.single.displayName, 'work');
      expect(cols.single.components, {'VEVENT', 'VTODO'});
    });
  });

  group('calendar-query', () {
    final cal = Uri.parse('http://dav.test:5232/test/sasa-calendar/');
    final tasks = Uri.parse('http://dav.test:5232/test/sasa-tasks/');

    test('events: time-range filter in UTC, Depth 1, no expand', () async {
      final dav = FakeDav();
      final objs = await clientFor(dav)
          .queryEvents(cal, p(2026, 11, 2), p(2026, 11, 9));
      final req = dav.seen.single;
      expect(req.method, 'REPORT');
      expect(req.headers['Depth'], '1');
      expect(req.body, contains('<C:comp-filter name="VEVENT">'));
      expect(
        req.body,
        contains('start="20261101T230000Z" end="20261108T230000Z"'),
      );
      expect(req.body, isNot(contains('expand')));
      expect(objs, hasLength(6));
      expect(
        objs.first.uri,
        Uri.parse('http://dav.test:5232/test/sasa-calendar/allday-busy.ics'),
      );
      expect(objs.first.etag, startsWith('"c799'));
      expect(objs.first.data, startsWith('BEGIN:VCALENDAR'));
    });

    test('open todos use a COMPLETED is-not-defined filter', () async {
      final dav = FakeDav();
      final objs = await clientFor(dav).queryOpenTodos(tasks);
      expect(dav.seen.single.body, contains('is-not-defined'));
      expect(objs, hasLength(3));
    });

    test('all todos', () async {
      final objs = await clientFor(FakeDav()).queryTodos(tasks);
      expect(objs, hasLength(4));
    });

    test('non-207 answer throws with status', () async {
      final dav = FakeDav(
        routes: {
          'REPORT /test/sasa-calendar/': (_) => http.Response('boom', 500),
        },
      );
      await expectLater(
        clientFor(dav).queryEvents(cal, z(2026, 1, 1), z(2027, 1, 1)),
        throwsA(
          isA<CalDavException>().having((e) => e.statusCode, 'status', 500),
        ),
      );
    });
  });

  test('formatUtc', () {
    expect(formatUtc(p(2026, 11, 2, 9, 5)), '20261102T080500Z');
  });
}
