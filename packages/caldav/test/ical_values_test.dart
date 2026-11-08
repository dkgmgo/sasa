import 'package:sasa_caldav/sasa_caldav.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'helpers.dart';

void main() {
  final zones = parisZones();

  group('parseIcalDateTime', () {
    test('DATE', () {
      final d = parseIcalDateTime('20261106');
      expect(d.isDate, isTrue);
      expect(d.wall, DateTime.utc(2026, 11, 6));
      expect(d.instant(zones), p(2026, 11, 6));
    });

    test('UTC DATE-TIME', () {
      final d = parseIcalDateTime('20261104T080000Z');
      expect(d.isUtc, isTrue);
      expect(d.instant(zones), z(2026, 11, 4, 8));
    });

    test('TZID DATE-TIME, both sides of the DST change', () {
      expect(
        parseIcalDateTime(
          '20261019T103000',
          tzid: 'Europe/Paris',
        ).instant(zones),
        z(2026, 10, 19, 8, 30),
      );
      expect(
        parseIcalDateTime(
          '20261026T103000',
          tzid: 'Europe/Paris',
        ).instant(zones),
        z(2026, 10, 26, 9, 30),
      );
    });

    test('other TZID than the default', () {
      expect(
        parseIcalDateTime(
          '20261102T090000',
          tzid: 'America/New_York',
        ).instant(zones),
        z(2026, 11, 2, 14),
      );
    });

    test('floating time uses the default zone', () {
      expect(
        parseIcalDateTime('20261102T090000').instant(zones),
        z(2026, 11, 2, 8),
      );
    });

    test('VALUE=DATE forces a date', () {
      expect(
        parseIcalDateTime('20261102T090000', forceDate: true).isDate,
        isTrue,
      );
    });

    test('garbage throws FormatException', () {
      expect(() => parseIcalDateTime('2026-11-02'), throwsFormatException);
    });
  });

  group('ZoneResolver', () {
    test('IANA name', () {
      expect(zones.resolve('America/New_York').name, 'America/New_York');
    });

    test('prefixed ids resolve to the trailing Area/City', () {
      expect(
        zones
            .resolve('/freeassociation.sourceforge.net/Tzfile/Europe/Berlin')
            .name,
        'Europe/Berlin',
      );
      expect(
        zones.resolve('/mozilla.org/20070129_1/America/Argentina/Salta').name,
        'America/Argentina/Salta',
      );
    });

    test('UTC', () => expect(zones.resolve('UTC'), tz.UTC));

    test('unknown or missing TZID falls back to the default', () {
      expect(zones.resolve('W. Europe Standard Time'), paris);
      expect(zones.resolve(null), paris);
    });
  });

  group('parseIcalDuration', () {
    test('time parts are exact', () {
      expect(
        parseIcalDuration('PT1H30M'),
        const IcalDuration(time: Duration(hours: 1, minutes: 30)),
      );
    });

    test('days and weeks are nominal', () {
      expect(parseIcalDuration('P1W2D'), const IcalDuration(days: 9));
      expect(
        parseIcalDuration('P1DT2H'),
        const IcalDuration(days: 1, time: Duration(hours: 2)),
      );
    });

    test('negative', () {
      expect(
        parseIcalDuration('-PT15M'),
        const IcalDuration(time: Duration(minutes: -15)),
      );
    });

    test('invalid', () {
      for (final s in ['P', 'PT', '1H', 'P1H']) {
        expect(() => parseIcalDuration(s), throwsFormatException, reason: s);
      }
    });
  });
}
