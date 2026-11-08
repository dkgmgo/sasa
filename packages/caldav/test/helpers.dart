import 'dart:io';

import 'package:sasa_caldav/sasa_caldav.dart';
import 'package:sasa_core/sasa_core.dart' show locationFor, utcInstant;
import 'package:timezone/timezone.dart' as tz;

/// Europe/Paris, the default zone of every test.
final tz.Location paris = locationFor('Europe/Paris');

ZoneResolver parisZones() => ZoneResolver(paris);

/// UTC instant of a Paris wall-clock time.
DateTime p(int y, int m, int d, [int h = 0, int min = 0]) =>
    utcInstant(tz.TZDateTime(paris, y, m, d, h, min));

/// UTC instant.
DateTime z(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

/// Text of `test/fixtures/<path>`.
String fixture(String path) => File('test/fixtures/$path').readAsStringSync();

/// Text of a seed file shared with tools/radicale-test.
String seed(String path) =>
    File('../../tools/radicale-test/seed/$path').readAsStringSync();

/// Wraps VEVENT/VTODO lines in a VCALENDAR.
String vcal(String body) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\n'
    '${body.trim().split('\n').map((l) => l.trim()).join('\r\n')}\r\n'
    'END:VCALENDAR\r\n';
