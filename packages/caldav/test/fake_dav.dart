import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

/// A recorded request.
typedef Seen = ({
  String method,
  Uri uri,
  Map<String, String> headers,
  String body,
});

/// In-memory CalDAV server replaying recorded Radicale responses.
final class FakeDav {
  FakeDav({Map<String, http.Response Function(http.Request)>? routes})
    : routes = routes ?? radicaleRoutes();

  /// Keyed by `METHOD path`.
  final Map<String, http.Response Function(http.Request)> routes;
  final List<Seen> seen = [];

  late final http.Client client = MockClient((req) async {
    seen.add((
      method: req.method,
      uri: req.url,
      headers: req.headers,
      body: req.body,
    ));
    final route = routes['${req.method} ${req.url.path}'];
    return route == null ? http.Response('not found', 404) : route(req);
  });
}

http.Response multistatus(String body) => http.Response(
  body,
  207,
  headers: {'content-type': 'text/xml; charset=utf-8'},
);

/// Routes answering like tools/radicale-test after seeding.
Map<String, http.Response Function(http.Request)> radicaleRoutes() => {
  'PROPFIND /.well-known/caldav': (_) =>
      http.Response('Redirected to /', 301, headers: {'location': '/'}),
  'PROPFIND /': (_) => multistatus(fixture('radicale/propfind-principal.xml')),
  'PROPFIND /test/': (req) => multistatus(
    fixture(
      req.headers['Depth'] == '1'
          ? 'radicale/propfind-collections.xml'
          : 'radicale/propfind-home-set.xml',
    ),
  ),
  'REPORT /test/sasa-calendar/': (_) =>
      multistatus(fixture('radicale/report-events-2026-11-01_10.xml')),
  'REPORT /test/sasa-tasks/': (req) => multistatus(
    req.body.contains('is-not-defined')
        ? fixture('radicale/report-todos-open.xml')
        : fixture('radicale/report-todos-all.xml'),
  ),
};
