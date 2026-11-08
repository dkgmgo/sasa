import 'package:sasa_caldav/sasa_caldav.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('unfoldLines', () {
    test('joins continuation lines starting with space or tab', () {
      expect(
        unfoldLines('DESCRIPTION:Hello\r\n  world\r\n\tagain\r\nSUMMARY:x\r\n'),
        ['DESCRIPTION:Hello worldagain', 'SUMMARY:x'],
      );
    });

    test('accepts LF-only line ends and skips blank lines', () {
      expect(unfoldLines('A:1\n\nB:2\n'), ['A:1', 'B:2']);
    });
  });

  group('parseContentLine', () {
    test('name, params and value', () {
      final p = parseContentLine(
        'dtstart;tzid=Europe/Paris;VALUE=DATE-TIME:20261102T140000',
      )!;
      expect(p.name, 'DTSTART');
      expect(p.param('TZID'), 'Europe/Paris');
      expect(p.param('value'), 'DATE-TIME');
      expect(p.value, '20261102T140000');
    });

    test('quoted parameter values may contain : ; ,', () {
      final p = parseContentLine(
        'ATTENDEE;CN="Doe, J: PhD";ROLE=REQ-PARTICIPANT:mailto:j@example.org',
      )!;
      expect(p.param('CN'), 'Doe, J: PhD');
      expect(p.value, 'mailto:j@example.org');
    });

    test('value keeps further colons', () {
      expect(parseContentLine('URL:https://a.b/c')!.value, 'https://a.b/c');
    });

    test('line without colon is ignored', () {
      expect(parseContentLine('garbage'), isNull);
    });
  });

  group('parseIcal', () {
    test('builds nested components', () {
      final roots = parseIcal(
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:1\r\n'
        'BEGIN:VALARM\r\nACTION:DISPLAY\r\nEND:VALARM\r\nEND:VEVENT\r\n'
        'END:VCALENDAR\r\n',
      );
      expect(roots, hasLength(1));
      final cal = roots.single;
      expect(cal.name, 'VCALENDAR');
      expect(cal.property('version')!.value, '2.0');
      final ev = cal.childrenNamed('VEVENT').single;
      expect(ev.property('UID')!.value, '1');
      expect(
        ev.childrenNamed('VALARM').single.property('ACTION')!.value,
        'DISPLAY',
      );
    });

    test('mismatched END throws FormatException', () {
      expect(
        () => parseIcal('BEGIN:VCALENDAR\nBEGIN:VEVENT\nEND:VCALENDAR\n'),
        throwsFormatException,
      );
    });

    test('missing END throws FormatException', () {
      expect(() => parseIcal('BEGIN:VCALENDAR\n'), throwsFormatException);
    });

    test('parses seed files', () {
      for (final f in [
        'events/lab-networks-weekly.ics',
        'tasks/review-paper.ics',
      ]) {
        expect(parseIcal(seed(f)).single.name, 'VCALENDAR');
      }
    });
  });

  group('text values', () {
    test('unescapeText', () {
      expect(unescapeText(r'a\, b\; c\\d\ne\Nf'), 'a, b; c\\d\ne\nf');
    });

    test('splitTextList splits on unescaped commas only', () {
      expect(splitTextList(r'review,research,a\,b'), [
        'review',
        'research',
        'a,b',
      ]);
    });
  });
}
