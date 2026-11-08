import 'package:sasa_caldav/sasa_caldav.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Events of [ics] overlapping `[from, to)`, Paris default zone.
List<CalEvent> expand(String ics, DateTime from, DateTime to) => eventsFromIcal(
  ics,
  calendarName: 'Cal',
  from: from,
  to: to,
  zones: parisZones(),
);

List<DateTime> starts(String ics, DateTime from, DateTime to) => [
  for (final e in expand(ics, from, to)) e.start,
];

void main() {
  group('seed: weekly lab (DST, EXDATE, moved override)', () {
    final lab = seed('events/lab-networks-weekly.ics');

    test('wall time stays 10:30 Paris across the October DST change', () {
      final ev = expand(lab, p(2026, 10, 19), p(2026, 11, 3));
      expect(
        [for (final e in ev) e.start],
        [
          z(2026, 10, 19, 8, 30), // CEST
          z(2026, 10, 26, 9, 30), // CET
          z(2026, 11, 2, 9, 30),
        ],
      );
      expect(ev.first.end, z(2026, 10, 19, 10, 30));
      expect(ev.first.title, 'Networks lab');
      expect(ev.first.location, 'Lab room 3');
      expect(ev.first.uid, 'sasa-seed-lab-networks');
    });

    test('EXDATE removes 9 Nov, override moves 16 Nov to 14:00', () {
      final ev = expand(lab, p(2026, 11, 2), p(2026, 11, 23));
      expect(
        [for (final e in ev) (e.start, e.title)],
        [
          (p(2026, 11, 2, 10, 30), 'Networks lab'),
          (p(2026, 11, 16, 14), 'Networks lab (moved)'),
        ],
      );
      expect(ev.last.end, p(2026, 11, 16, 16));
    });

    test('moved instance is absent from its original slot', () {
      expect(
        starts(lab, p(2026, 11, 16, 10, 30), p(2026, 11, 16, 11)),
        isEmpty,
      );
    });

    test('moved instance appears in its new slot only', () {
      expect(starts(lab, p(2026, 11, 16, 15), p(2026, 11, 16, 15, 30)), [
        p(2026, 11, 16, 14),
      ]);
    });

    test('UNTIL (UTC) ends the series on 21 Dec', () {
      expect(starts(lab, p(2026, 12, 14), p(2027, 1, 31)), [
        p(2026, 12, 14, 10, 30),
        p(2026, 12, 21, 10, 30),
      ]);
    });

    test('nothing before DTSTART', () {
      expect(starts(lab, p(2026, 8, 1), p(2026, 9, 7)), isEmpty);
    });
  });

  group('RRULE variants', () {
    test('COUNT', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:c
        DTSTART;TZID=Europe/Paris:20261102T090000
        DTEND;TZID=Europe/Paris:20261102T100000
        RRULE:FREQ=DAILY;COUNT=3
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 1), p(2026, 12, 1)), [
        p(2026, 11, 2, 9),
        p(2026, 11, 3, 9),
        p(2026, 11, 4, 9),
      ]);
    });

    test('COUNT is counted from DTSTART, not from the range start', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:c
        DTSTART;TZID=Europe/Paris:20261102T090000
        RRULE:FREQ=DAILY;COUNT=3
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 4), p(2026, 12, 1)), [p(2026, 11, 4, 9)]);
    });

    test('WKST=SU is accepted (dropped)', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:w
        DTSTART;TZID=Europe/Paris:20261103T090000
        DTEND;TZID=Europe/Paris:20261103T100000
        RRULE:FREQ=WEEKLY;BYDAY=TU,TH;WKST=SU
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 2), p(2026, 11, 9)), [
        p(2026, 11, 3, 9),
        p(2026, 11, 5, 9),
      ]);
    });

    test('monthly last Friday', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:m
        DTSTART;TZID=Europe/Paris:20261030T160000
        DTEND;TZID=Europe/Paris:20261030T170000
        RRULE:FREQ=MONTHLY;BYDAY=-1FR
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 1), p(2027, 1, 1)), [
        p(2026, 11, 27, 16),
        p(2026, 12, 25, 16),
      ]);
    });

    test('DTSTART counts (also toward COUNT) when it does not match', () {
      // Starts on a Sunday, rule says Mondays.
      final ics = vcal('''
        BEGIN:VEVENT
        UID:s
        DTSTART;TZID=Europe/Paris:20261101T090000
        RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=3
        END:VEVENT''');
      expect(starts(ics, p(2026, 10, 31), p(2026, 11, 30)), [
        p(2026, 11, 1, 9),
        p(2026, 11, 2, 9),
        p(2026, 11, 9, 9),
      ]);
    });

    test('DTSTART without COUNT', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:s
        DTSTART;TZID=Europe/Paris:20261101T090000
        RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20261110T000000Z
        END:VEVENT''');
      expect(starts(ics, p(2026, 10, 31), p(2026, 11, 30)), [
        p(2026, 11, 1, 9),
        p(2026, 11, 2, 9),
        p(2026, 11, 9, 9),
      ]);
    });

    test('RDATE adds instances, also from another zone', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:r
        DTSTART;TZID=Europe/Paris:20261102T090000
        DTEND;TZID=Europe/Paris:20261102T100000
        RDATE;TZID=Europe/Paris:20261105T110000,20261106T110000
        RDATE:20261110T130000Z
        END:VEVENT''');
      final ev = expand(ics, p(2026, 11, 1), p(2026, 11, 30));
      expect(
        [for (final e in ev) e.start],
        [
          p(2026, 11, 2, 9),
          p(2026, 11, 5, 11),
          p(2026, 11, 6, 11),
          z(2026, 11, 10, 13),
        ],
      );
      expect(ev.last.end, z(2026, 11, 10, 14));
    });

    test('EXDATE in UTC matches a TZID instance', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:x
        DTSTART;TZID=Europe/Paris:20261102T090000
        RRULE:FREQ=DAILY;COUNT=3
        EXDATE:20261103T080000Z
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 1), p(2026, 11, 30)), [
        p(2026, 11, 2, 9),
        p(2026, 11, 4, 9),
      ]);
    });

    test('unreadable RRULE: the event occurs once', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:bad
        DTSTART;TZID=Europe/Paris:20261102T090000
        RRULE:FREQ=SOMETIMES
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 1), p(2026, 12, 1)), [p(2026, 11, 2, 9)]);
    });

    test('UTC series stays at the same UTC time across DST', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:u
        DTSTART:20261019T080000Z
        DTEND:20261019T090000Z
        RRULE:FREQ=WEEKLY
        END:VEVENT''');
      expect(starts(ics, z(2026, 10, 19), z(2026, 10, 27)), [
        z(2026, 10, 19, 8),
        z(2026, 10, 26, 8),
      ]);
    });

    test('a range far after DTSTART stays fast and correct', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:old
        DTSTART;TZID=Europe/Paris:20100104T090000
        DTEND;TZID=Europe/Paris:20100104T091500
        RRULE:FREQ=DAILY
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 2), p(2026, 11, 3)), [p(2026, 11, 2, 9)]);
    });
  });

  group('durations', () {
    test('DURATION in days is nominal across DST', () {
      // 24 Oct 12:00 CEST + P1D = 25 Oct 12:00 CET (25 h later).
      final ics = vcal('''
        BEGIN:VEVENT
        UID:d
        DTSTART;TZID=Europe/Paris:20261024T120000
        DURATION:P1D
        END:VEVENT''');
      final e = expand(ics, p(2026, 10, 24), p(2026, 10, 26)).single;
      expect(e.end, p(2026, 10, 25, 12));
      expect(e.end.difference(e.start), const Duration(hours: 25));
    });

    test('DTEND gives the same exact length to every instance', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:n
        DTSTART;TZID=Europe/Paris:20261024T230000
        DTEND;TZID=Europe/Paris:20261025T010000
        RRULE:FREQ=DAILY;COUNT=2
        END:VEVENT''');
      for (final e in expand(ics, p(2026, 10, 24), p(2026, 10, 27))) {
        expect(e.end.difference(e.start), const Duration(hours: 2));
      }
    });

    test('no DTEND/DURATION: timed is zero-length, all-day is one day', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:t
        DTSTART;TZID=Europe/Paris:20261102T090000
        END:VEVENT
        BEGIN:VEVENT
        UID:a
        DTSTART;VALUE=DATE:20261103
        END:VEVENT''');
      final ev = expand(ics, p(2026, 11, 2), p(2026, 11, 4));
      expect(ev[0].end, ev[0].start);
      expect(ev[1].allDay, isTrue);
      expect(ev[1].end, DateTime.utc(2026, 11, 4));
    });

    test('zero-length event at the range start is included, at end not', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:t
        DTSTART;TZID=Europe/Paris:20261102T090000
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 2, 9), p(2026, 11, 2, 10)), hasLength(1));
      expect(starts(ics, p(2026, 11, 2, 8), p(2026, 11, 2, 9)), isEmpty);
    });
  });

  group('all-day', () {
    test('seed busy and free all-day events', () {
      final busy = expand(
        seed('events/allday-busy.ics'),
        p(2026, 11, 6),
        p(2026, 11, 7),
      ).single;
      expect(busy.allDay, isTrue);
      expect(busy.busy, isTrue);
      expect(busy.start, DateTime.utc(2026, 11, 6));
      expect(busy.end, DateTime.utc(2026, 11, 7));

      final free = expand(
        seed('events/allday-free.ics'),
        p(2026, 11, 5),
        p(2026, 11, 6),
      ).single;
      expect(free.busy, isFalse);
    });

    test('all-day is matched against the range in the default zone', () {
      final ics = seed('events/allday-busy.ics'); // Paris 6 Nov
      // 5 Nov 23:30 UTC is already 6 Nov 00:30 in Paris.
      expect(
        starts(ics, z(2026, 11, 5, 23, 30), z(2026, 11, 5, 23, 45)),
        hasLength(1),
      );
      // 5 Nov 22:00–23:00 UTC is still 5 Nov in Paris.
      expect(starts(ics, z(2026, 11, 5, 22), z(2026, 11, 5, 23)), isEmpty);
    });

    test('recurring all-day with EXDATE as DATE', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:ad
        DTSTART;VALUE=DATE:20261102
        DTEND;VALUE=DATE:20261103
        RRULE:FREQ=DAILY;UNTIL=20261105
        EXDATE;VALUE=DATE:20261103
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 1), p(2026, 11, 30)), [
        DateTime.utc(2026, 11, 2),
        DateTime.utc(2026, 11, 4),
        DateTime.utc(2026, 11, 5),
      ]);
    });

    test('multi-day all-day event', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:conf
        DTSTART;VALUE=DATE:20261109
        DTEND;VALUE=DATE:20261112
        END:VEVENT''');
      final e = expand(ics, p(2026, 11, 11, 12), p(2026, 11, 11, 13)).single;
      expect(e.end, DateTime.utc(2026, 11, 12));
    });
  });

  group('status, transparency, overrides', () {
    test('seed TRANSP:TRANSPARENT event is not busy', () {
      final e = expand(
        seed('events/optional-seminar.ics'),
        p(2026, 11, 3),
        p(2026, 11, 4),
      ).single;
      expect(e.busy, isFalse);
      expect(e.start, p(2026, 11, 3, 16));
    });

    test('seed UTC event without TZID', () {
      final e = expand(
        seed('events/collaborator-call-utc.ics'),
        p(2026, 11, 4),
        p(2026, 11, 5),
      ).single;
      expect(e.start, z(2026, 11, 4, 8));
      expect(e.end, z(2026, 11, 4, 9));
      expect(e.busy, isTrue);
    });

    test('cancelled master and cancelled override are dropped', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:gone
        STATUS:CANCELLED
        DTSTART;TZID=Europe/Paris:20261102T090000
        END:VEVENT
        BEGIN:VEVENT
        UID:s
        DTSTART;TZID=Europe/Paris:20261102T090000
        RRULE:FREQ=DAILY;COUNT=2
        END:VEVENT
        BEGIN:VEVENT
        UID:s
        RECURRENCE-ID;TZID=Europe/Paris:20261103T090000
        DTSTART;TZID=Europe/Paris:20261103T090000
        STATUS:CANCELLED
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 1), p(2026, 11, 30)), [p(2026, 11, 2, 9)]);
    });

    test('override without master (invited to one instance) is kept', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:orphan
        RECURRENCE-ID;TZID=Europe/Paris:20261103T090000
        DTSTART;TZID=Europe/Paris:20261103T093000
        DTEND;TZID=Europe/Paris:20261103T100000
        SUMMARY:One instance
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 1), p(2026, 11, 30)), [
        p(2026, 11, 3, 9, 30),
      ]);
    });

    test('override without DTEND keeps the master duration', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:s
        DTSTART;TZID=Europe/Paris:20261102T090000
        DTEND;TZID=Europe/Paris:20261102T103000
        RRULE:FREQ=DAILY;COUNT=2
        END:VEVENT
        BEGIN:VEVENT
        UID:s
        RECURRENCE-ID;TZID=Europe/Paris:20261103T090000
        DTSTART;TZID=Europe/Paris:20261103T140000
        END:VEVENT''');
      final last = expand(ics, p(2026, 11, 1), p(2026, 11, 30)).last;
      expect(last.end, p(2026, 11, 3, 15, 30));
    });

    test('floating time and unknown TZID use the default zone', () {
      final ics = vcal('''
        BEGIN:VEVENT
        UID:f
        DTSTART:20261102T090000
        DTEND:20261102T100000
        END:VEVENT
        BEGIN:VEVENT
        UID:w
        DTSTART;TZID=W. Europe Standard Time:20261102T110000
        DTEND;TZID=W. Europe Standard Time:20261102T120000
        END:VEVENT''');
      expect(starts(ics, p(2026, 11, 2), p(2026, 11, 3)), [
        p(2026, 11, 2, 9),
        p(2026, 11, 2, 11),
      ]);
    });

    test('escaped text and missing summary', () {
      final ics = vcal(r'''
        BEGIN:VEVENT
        UID:t
        DTSTART:20261102T090000Z
        DESCRIPTION:Line 1\nLine 2\, with comma
        END:VEVENT''');
      final e = expand(ics, z(2026, 11, 2), z(2026, 11, 3)).single;
      expect(e.title, '');
      expect(e.description, 'Line 1\nLine 2, with comma');
      expect(e.location, isNull);
      expect(e.calendarName, 'Cal');
    });
  });
}
