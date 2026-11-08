import 'package:sasa_caldav/src/dav/multistatus.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'helpers.dart';

void main() {
  test('recorded collections: 200 props only, 404 props dropped', () {
    final rs = parseMultistatus(fixture('radicale/propfind-collections.xml'));
    expect(
      [for (final r in rs) r.href],
      ['/test/', '/test/sasa-calendar/', '/test/sasa-tasks/'],
    );
    expect(rs[0].prop(davNs, 'displayname'), isNull);
    expect(rs[1].prop(davNs, 'displayname')!.innerText, 'Sasa test calendar');
    expect(
      hasChild(rs[1].prop(davNs, 'resourcetype'), caldavNs, 'calendar'),
      isTrue,
    );
    expect(
      hasChild(rs[0].prop(davNs, 'resourcetype'), caldavNs, 'calendar'),
      isFalse,
    );
  });

  test('namespace prefixes do not matter', () {
    final rs = parseMultistatus('''
      <x:multistatus xmlns:x="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
        <x:response><x:href>/a/</x:href>
          <x:propstat><x:prop><cal:calendar-home-set><x:href>/home/</x:href>
          </cal:calendar-home-set></x:prop>
          <x:status>HTTP/1.1 200 OK</x:status></x:propstat>
        </x:response>
      </x:multistatus>''');
    expect(hrefIn(rs.single.prop(caldavNs, 'calendar-home-set')), '/home/');
  });

  test('response-level status', () {
    final rs = parseMultistatus(
      '<multistatus xmlns="DAV:"><response><href>/gone</href>'
      '<status>HTTP/1.1 404 Not Found</status></response></multistatus>',
    );
    expect(rs.single.status, 404);
    expect(rs.single.props, isEmpty);
  });

  test('statusCode', () {
    expect(statusCode('HTTP/1.1 200 OK'), 200);
    expect(statusCode('nonsense'), isNull);
    expect(statusCode(null), isNull);
  });

  test('bad XML or wrong root throws FormatException', () {
    expect(() => parseMultistatus('<oops'), throwsFormatException);
    expect(
      () => parseMultistatus('<propfind xmlns="DAV:"/>'),
      throwsFormatException,
    );
  });
}
