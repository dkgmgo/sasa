import 'dart:convert';
import 'dart:math';

import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('uuidV4', () {
    test('has the RFC 4122 version-4 layout', () {
      final r = Random(1);
      for (var i = 0; i < 100; i++) {
        expect(
          uuidV4(r),
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
              r'[0-9a-f]{12}$',
            ),
          ),
        );
      }
    });

    test('is deterministic for a seeded Random and unique in practice', () {
      expect(uuidV4(Random(7)), uuidV4(Random(7)));
      final r = Random(3);
      expect({for (var i = 0; i < 1000; i++) uuidV4(r)}, hasLength(1000));
    });
  });

  group('device ids', () {
    test('accept folder-safe names', () {
      for (final ok in ['linux-3f2a9c1b', 'android.phone', 'A_1']) {
        expect(isValidDeviceId(ok), isTrue, reason: ok);
      }
    });

    test('reject names that are unsafe as a folder', () {
      for (final bad in ['', '.', '..', '.hidden', 'a/b', r'a\b', 'é', ' x']) {
        expect(isValidDeviceId(bad), isFalse, reason: bad);
      }
      expect(isValidDeviceId('x' * 65), isFalse);
    });

    test('generateDeviceId uses the prefix and a random suffix', () {
      final id = generateDeviceId('linux', Random(1));
      expect(id, matches(RegExp(r'^linux-[0-9a-f]{8}$')));
      expect(isValidDeviceId(id), isTrue);
    });
  });

  group('LogEvent', () {
    final e = LogEvent(
      id: '0b7f0c8e-2a51-4c2a-9b55-1a3c1b1b2c3d',
      ts: z(2026, 11, 8, 9, 30),
      device: 'linux-1',
      type: 'energy.checkin',
      v: 1,
      data: const {'energy': 'high'},
    );

    test('serialises to one JSON line with the documented keys', () {
      final line = e.toLine();
      expect(line, isNot(contains('\n')));
      expect(jsonDecode(line), {
        'id': '0b7f0c8e-2a51-4c2a-9b55-1a3c1b1b2c3d',
        'ts': '2026-11-08T09:30:00.000Z',
        'device': 'linux-1',
        'type': 'energy.checkin',
        'v': 1,
        'data': {'energy': 'high'},
      });
    });

    test('round-trips', () {
      expect(LogEvent.fromLine(e.toLine()), e);
    });

    test('escapes newlines inside data, so a line stays a line', () {
      final withNote = LogEvent(
        id: 'x',
        ts: z(2026, 1, 1),
        device: 'd',
        type: 't',
        v: 1,
        data: const {'note': 'two\nlines'},
      );
      expect(withNote.toLine(), isNot(contains('\n')));
      expect(LogEvent.fromLine(withNote.toLine()).data['note'], 'two\nlines');
    });

    test('ts is normalised to UTC', () {
      final local = LogEvent(
        id: 'x',
        ts: DateTime.parse('2026-11-08T10:30:00+01:00'),
        device: 'd',
        type: 't',
        v: 1,
        data: const {},
      );
      expect(local.ts, z(2026, 11, 8, 9, 30));
      expect(local.ts.isUtc, isTrue);
    });

    test('rejects malformed envelopes with a FormatException', () {
      final good = jsonDecode(e.toLine()) as Map<String, Object?>;
      Map<String, Object?> without(String k) => Map.of(good)..remove(k);
      final bad = <String, Object?>{
        'not json': 'not json',
        'array': '[1,2]',
        'no id': jsonEncode(without('id')),
        'empty id': jsonEncode({...good, 'id': ''}),
        'no ts': jsonEncode(without('ts')),
        'ts without zone': jsonEncode({...good, 'ts': '2026-11-08T09:30:00'}),
        'no device': jsonEncode(without('device')),
        'bad device': jsonEncode({...good, 'device': '../x'}),
        'no type': jsonEncode(without('type')),
        'no v': jsonEncode(without('v')),
        'v zero': jsonEncode({...good, 'v': 0}),
        'data not object': jsonEncode({...good, 'data': 3}),
      };
      for (final MapEntry(:key, :value) in bad.entries) {
        expect(
          () => LogEvent.fromLine(value! as String),
          throwsFormatException,
          reason: key,
        );
      }
    });

    test('missing data reads as empty, unknown envelope keys are ignored', () {
      final good = jsonDecode(e.toLine()) as Map<String, Object?>;
      final parsed = LogEvent.fromLine(
        jsonEncode({...good, 'extra': true}..remove('data')),
      );
      expect(parsed.data, isEmpty);
    });

    test('orders by ts, then device, then id', () {
      LogEvent at(DateTime ts, String device, String id) => LogEvent(
        id: id,
        ts: ts,
        device: device,
        type: 't',
        v: 1,
        data: const {},
      );
      final a = at(z(2026, 1, 1, 9), 'b', '2');
      final b = at(z(2026, 1, 1, 10), 'a', '1');
      final c = at(z(2026, 1, 1, 10), 'b', '1');
      final d = at(z(2026, 1, 1, 10), 'b', '2');
      expect(([d, c, b, a]..sort()), [a, b, c, d]);
    });

    test('logFileName uses the UTC month of the event', () {
      expect(logFileName(z(2026, 11, 30, 23, 59)), 'log-2026-11.jsonl');
      // 1 Dec 00:30 in Paris is still 30 Nov in UTC.
      expect(logFileName(p(2026, 12, 1, 0, 30)), 'log-2026-11.jsonl');
      expect(logFileName(z(2027, 1, 1)), 'log-2027-01.jsonl');
    });
  });
}
