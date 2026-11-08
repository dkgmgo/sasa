/// CalDAV client: discovery, collection listing and
/// `calendar-query` reports (RFC 4791, RFC 6764).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' show XmlStringExtension;

import 'multistatus.dart';

/// Login for HTTP Basic auth. [toString] never shows the password.
final class CalDavCredentials {
  const CalDavCredentials(this.username, this.password);

  final String username;
  final String password;

  String get _basic =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  @override
  String toString() => 'CalDavCredentials($username, ***)';
}

/// A CalDAV request failed. Messages hold the method, URL and status only:
/// never credentials or response bodies.
class CalDavException implements Exception {
  CalDavException(this.message, {this.statusCode, this.uri});

  final String message;
  final int? statusCode;
  final Uri? uri;

  @override
  String toString() =>
      'CalDavException: $message'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}'
      '${uri == null ? '' : ' at ${_redact(uri!)}'}';
}

/// The server rejected the credentials (401/403).
final class CalDavAuthException extends CalDavException {
  CalDavAuthException(super.message, {super.statusCode, super.uri});
}

/// [uri] without user-info, for messages.
String _redact(Uri uri) => uri.replace(userInfo: '').toString();

/// A calendar collection (`<C:calendar/>` resource type).
final class CalDavCollection {
  const CalDavCollection({
    required this.uri,
    required this.displayName,
    required this.components,
    this.ctag,
    this.color,
  });

  /// Absolute URL of the collection.
  final Uri uri;

  /// `displayname`, or the last path segment when unset.
  final String displayName;

  /// Supported component names, e.g. `{VEVENT}` or `{VTODO}`. A server that
  /// does not advertise any is assumed to accept VEVENT and VTODO.
  final Set<String> components;

  /// `CS:getctag`: changes whenever the collection changes.
  final String? ctag;

  /// `ICAL:calendar-color`, e.g. `#FF0000FF`.
  final String? color;

  bool get hasEvents => components.contains('VEVENT');
  bool get hasTasks => components.contains('VTODO');

  @override
  String toString() => 'CalDavCollection($displayName, $uri, $components)';
}

/// One calendar object resource (an `.ics` file) from a REPORT.
final class CalendarObject {
  const CalendarObject({required this.uri, required this.data, this.etag});

  final Uri uri;

  /// iCalendar text.
  final String data;
  final String? etag;
}

/// Low-level CalDAV client. It only sends PROPFIND and REPORT: it never
/// writes to the server.
///
/// Redirects are followed by hand (up to 5), and credentials are only sent
/// to the origin of [baseUri].
final class CalDavClient {
  CalDavClient({
    required this.baseUri,
    required http.Client httpClient,
    this.credentials,
  }) : _http = httpClient;

  /// Server URL as entered by the user, e.g. `https://dav.example.org/`.
  final Uri baseUri;
  final CalDavCredentials? credentials;
  final http.Client _http;

  static const _maxRedirects = 5;

  /// Finds the current user's principal URL (RFC 6764 §6).
  ///
  /// Tries `/.well-known/caldav` and [baseUri] (the latter first when it has
  /// a path, e.g. a reverse-proxied `/radicale/`).
  Future<Uri> discoverPrincipal() async {
    final wellKnown = baseUri.resolve('/.well-known/caldav');
    final hasPath = baseUri.path.isNotEmpty && baseUri.path != '/';
    final candidates = hasPath ? [baseUri, wellKnown] : [wellKnown, baseUri];
    CalDavException? last;
    for (final uri in candidates) {
      try {
        final (responses, at) = await _propfind(
          uri,
          depth: 0,
          props: '<D:current-user-principal/>',
        );
        for (final r in responses) {
          final href = hrefIn(r.prop(davNs, 'current-user-principal'));
          if (href != null) return at.resolve(href);
        }
        last = CalDavException('No current-user-principal', uri: uri);
      } on CalDavAuthException {
        rethrow;
      } on CalDavException catch (e) {
        last = e;
      }
    }
    throw last ?? CalDavException('Principal discovery failed', uri: baseUri);
  }

  /// `calendar-home-set` of [principal].
  Future<Uri> calendarHomeSet(Uri principal) async {
    final (responses, at) = await _propfind(
      principal,
      depth: 0,
      props: '<C:calendar-home-set/>',
    );
    for (final r in responses) {
      final href = hrefIn(r.prop(caldavNs, 'calendar-home-set'));
      if (href != null) return at.resolve(href);
    }
    throw CalDavException('No calendar-home-set', uri: principal);
  }

  /// Calendar collections directly under [home].
  Future<List<CalDavCollection>> listCollections(Uri home) async {
    final (responses, at) = await _propfind(
      home,
      depth: 1,
      props:
          '<D:resourcetype/><D:displayname/>'
          '<C:supported-calendar-component-set/>'
          '<CS:getctag/><ICAL:calendar-color/>',
    );
    final out = <CalDavCollection>[];
    for (final r in responses) {
      if (!hasChild(r.prop(davNs, 'resourcetype'), caldavNs, 'calendar')) {
        continue;
      }
      final uri = at.resolve(r.href);
      final comps = {
        for (final c
            in r
                    .prop(caldavNs, 'supported-calendar-component-set')
                    ?.childElements ??
                const <Never>[])
          if (c.name.local == 'comp')
            if (c.getAttribute('name') case final n?) n.toUpperCase(),
      };
      final name = r.prop(davNs, 'displayname')?.innerText.trim();
      final color = r.prop(appleIcalNs, 'calendar-color')?.innerText.trim();
      final ctag = r.prop(calendarServerNs, 'getctag')?.innerText.trim();
      out.add(
        CalDavCollection(
          uri: uri,
          displayName: name == null || name.isEmpty ? _lastSegment(uri) : name,
          components: comps.isEmpty ? const {'VEVENT', 'VTODO'} : comps,
          ctag: ctag == null || ctag.isEmpty ? null : ctag,
          color: color == null || color.isEmpty ? null : color,
        ),
      );
    }
    return out;
  }

  /// Principal → home set → collections.
  Future<List<CalDavCollection>> discoverCollections() async =>
      listCollections(await calendarHomeSet(await discoverPrincipal()));

  /// Resources in [collection] with a VEVENT overlapping `[from, to)`,
  /// as filtered by the server (no server-side expansion).
  Future<List<CalendarObject>> queryEvents(
    Uri collection,
    DateTime from,
    DateTime to,
  ) => _calendarQuery(
    collection,
    '<C:comp-filter name="VEVENT">'
    '<C:time-range start="${formatUtc(from)}" end="${formatUtc(to)}"/>'
    '</C:comp-filter>',
  );

  /// Resources in [collection] with a VTODO that has no `COMPLETED` date.
  /// `STATUS` must still be checked by the caller: a server-side STATUS
  /// text-match would also drop tasks that have no STATUS at all.
  Future<List<CalendarObject>> queryOpenTodos(Uri collection) => _calendarQuery(
    collection,
    '<C:comp-filter name="VTODO">'
    '<C:prop-filter name="COMPLETED"><C:is-not-defined/></C:prop-filter>'
    '</C:comp-filter>',
  );

  /// Every VTODO resource in [collection].
  Future<List<CalendarObject>> queryTodos(Uri collection) =>
      _calendarQuery(collection, '<C:comp-filter name="VTODO"/>');

  Future<List<CalendarObject>> _calendarQuery(
    Uri collection,
    String compFilter,
  ) async {
    final body =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<C:calendar-query xmlns:D="DAV:" xmlns:C="$caldavNs">'
        '<D:prop><D:getetag/><C:calendar-data/></D:prop>'
        '<C:filter><C:comp-filter name="VCALENDAR">$compFilter'
        '</C:comp-filter></C:filter>'
        '</C:calendar-query>';
    final (responses, at) = await _multistatus(
      'REPORT',
      collection,
      depth: 1,
      body: body,
    );
    return [
      for (final r in responses)
        if (r.prop(caldavNs, 'calendar-data')?.innerText case final data?
            when data.trim().isNotEmpty)
          CalendarObject(
            uri: at.resolve(r.href),
            data: data,
            etag: r.prop(davNs, 'getetag')?.innerText.trim(),
          ),
    ];
  }

  Future<(List<DavResponse>, Uri)> _propfind(
    Uri uri, {
    required int depth,
    required String props,
  }) => _multistatus(
    'PROPFIND',
    uri,
    depth: depth,
    body:
        '<?xml version="1.0" encoding="utf-8"?>'
        '<D:propfind xmlns:D="DAV:" xmlns:C="$caldavNs" '
        'xmlns:CS="$calendarServerNs" xmlns:ICAL="$appleIcalNs">'
        '<D:prop>$props</D:prop></D:propfind>',
  );

  /// Sends [method] and parses the 207 body. Returns the responses and the
  /// final URL after redirects (to resolve relative hrefs).
  Future<(List<DavResponse>, Uri)> _multistatus(
    String method,
    Uri uri, {
    required int depth,
    required String body,
  }) async {
    var current = uri;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final req = http.Request(method, current)
        ..followRedirects = false
        ..headers['Depth'] = '$depth'
        ..headers['Content-Type'] = 'application/xml; charset=utf-8'
        ..body = body;
      final auth = credentials;
      if (auth != null && _sameOrigin(current, baseUri)) {
        req.headers['Authorization'] = auth._basic;
      }
      final http.Response res;
      try {
        res = await http.Response.fromStream(await _http.send(req));
      } on http.ClientException catch (e) {
        throw CalDavException('$method failed: ${e.message}', uri: current);
      }
      final code = res.statusCode;
      if (code >= 300 && code < 400) {
        final loc = res.headers['location'];
        if (loc == null) {
          throw CalDavException(
            'Redirect without Location',
            statusCode: code,
            uri: current,
          );
        }
        current = current.resolve(loc);
        continue;
      }
      if (code == 401 || code == 403) {
        throw CalDavAuthException(
          '$method rejected credentials',
          statusCode: code,
          uri: current,
        );
      }
      if (code != 207) {
        throw CalDavException(
          '$method expected 207',
          statusCode: code,
          uri: current,
        );
      }
      try {
        return (parseMultistatus(utf8.decode(res.bodyBytes)), current);
      } on FormatException catch (e) {
        throw CalDavException('$method: ${e.message}', uri: current);
      }
    }
    throw CalDavException('Too many redirects', uri: uri);
  }
}

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme && a.host == b.host && a.port == b.port;

String _lastSegment(Uri uri) {
  final segs = uri.pathSegments.where((s) => s.isNotEmpty);
  return segs.isEmpty ? uri.toString() : segs.last;
}

/// `yyyyMMddTHHmmssZ` for CalDAV time ranges.
String formatUtc(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
      'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}
