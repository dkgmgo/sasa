/// WebDAV `207 Multi-Status` parsing (RFC 4918 §13).
library;

import 'package:xml/xml.dart';

/// `DAV:` namespace.
const String davNs = 'DAV:';

/// CalDAV namespace (RFC 4791).
const String caldavNs = 'urn:ietf:params:xml:ns:caldav';

/// CalendarServer extensions (`getctag`).
const String calendarServerNs = 'http://calendarserver.org/ns/';

/// Apple iCal extensions (`calendar-color`).
const String appleIcalNs = 'http://apple.com/ns/ical/';

/// One `<D:response>`: its href and the properties returned with 200 OK.
final class DavResponse {
  DavResponse(this.href, this.props, {this.status});

  /// Raw `<D:href>` text (usually an absolute path).
  final String href;

  /// Found properties, keyed by `{namespace}local`.
  final Map<String, XmlElement> props;

  /// Response-level `<D:status>` code, when given instead of propstats.
  final int? status;

  /// Property [local] in [ns], or null when absent or not 200 OK.
  XmlElement? prop(String ns, String local) => props['{$ns}$local'];
}

/// Parses a multistatus body. Throws [FormatException] on malformed XML or
/// a missing `<D:multistatus>` root.
List<DavResponse> parseMultistatus(String body) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } on XmlException catch (e) {
    throw FormatException('Invalid multistatus XML: ${e.message}');
  }
  final root = doc.rootElement;
  if (!_is(root, davNs, 'multistatus')) {
    throw FormatException('Expected DAV:multistatus, got ${root.name}');
  }
  return [
    for (final r in root.childElements.where((e) => _is(e, davNs, 'response')))
      ?_response(r),
  ];
}

DavResponse? _response(XmlElement r) {
  final href = _child(r, davNs, 'href')?.innerText.trim();
  if (href == null || href.isEmpty) return null;
  final props = <String, XmlElement>{};
  for (final ps in r.childElements.where((e) => _is(e, davNs, 'propstat'))) {
    final code = statusCode(_child(ps, davNs, 'status')?.innerText);
    if (code == null || code < 200 || code >= 300) continue;
    final prop = _child(ps, davNs, 'prop');
    if (prop == null) continue;
    for (final p in prop.childElements) {
      props['{${p.namespaceUri ?? ''}}${p.name.local}'] = p;
    }
  }
  final status = statusCode(_child(r, davNs, 'status')?.innerText);
  return DavResponse(href, props, status: status);
}

/// Code from a status line such as `HTTP/1.1 200 OK`.
int? statusCode(String? line) {
  if (line == null) return null;
  final m = RegExp(r'^\S+\s+(\d{3})').firstMatch(line.trim());
  return m == null ? null : int.parse(m.group(1)!);
}

bool _is(XmlElement e, String ns, String local) =>
    e.name.local == local && e.namespaceUri == ns;

XmlElement? _child(XmlElement e, String ns, String local) {
  for (final c in e.childElements) {
    if (_is(c, ns, local)) return c;
  }
  return null;
}

/// First `<D:href>` inside [e] (e.g. `current-user-principal`).
String? hrefIn(XmlElement? e) {
  if (e == null) return null;
  for (final c in e.descendantElements) {
    if (_is(c, davNs, 'href')) {
      final t = c.innerText.trim();
      if (t.isNotEmpty) return t;
    }
  }
  return null;
}

/// Whether [e] (a `resourcetype`) contains [ns]:[local].
bool hasChild(XmlElement? e, String ns, String local) =>
    e != null && e.childElements.any((c) => _is(c, ns, local));
