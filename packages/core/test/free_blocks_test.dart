import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Mon–Fri 08:00–19:00, 5-min buffer, 15-min minimum.
final defaults = FreeBlockSettings.defaults();

/// Every day 00:00–24:00, no buffer, 15-min minimum.
final allDayEveryDay = FreeBlockSettings(
  workingHours: WorkingHours.everyDay([w('00:00', '24:00')]),
  bufferMin: 0,
  minBlockMin: 15,
);

FreeBlock b(DateTime start, DateTime end) => FreeBlock(start: start, end: end);

List<FreeBlock> compute(
  DateTime from,
  DateTime to, {
  List<CalEvent> events = const [],
  FreeBlockSettings? settings,
}) => computeFreeBlocks(
  from: from,
  to: to,
  events: events,
  settings: settings ?? defaults,
  location: paris,
);

/// Monday 9 Nov 2026 (CET, UTC+1).
List<FreeBlock> monday({
  List<CalEvent> events = const [],
  FreeBlockSettings? settings,
}) => compute(
  p(2026, 11, 9),
  p(2026, 11, 10),
  events: events,
  settings: settings,
);

void main() {
  group('working hours', () {
    test('defaults are Mon–Fri 08:00–19:00, 5-min buffer, 15-min min', () {
      expect(defaults.bufferMin, 5);
      expect(defaults.minBlockMin, 15);
      for (var d = DateTime.monday; d <= DateTime.friday; d++) {
        expect(defaults.workingHours.windowsFor(d), [w('08:00', '19:00')]);
      }
      expect(defaults.workingHours.windowsFor(DateTime.saturday), isEmpty);
      expect(defaults.workingHours.windowsFor(DateTime.sunday), isEmpty);
    });

    test('empty weekday yields the whole working day in local time', () {
      // 08:00 CET is 07:00Z.
      expect(monday(), [b(z(2026, 11, 9, 7), z(2026, 11, 9, 18))]);
    });

    test('weekend yields nothing', () {
      expect(compute(p(2026, 11, 7), p(2026, 11, 9)), isEmpty);
    });

    test('several windows per day; overlapping windows are merged', () {
      final s = FreeBlockSettings(
        workingHours: WorkingHours({
          DateTime.monday: [
            w('08:00', '12:00'),
            w('14:00', '19:00'),
            w('11:00', '12:30'),
          ],
        }),
        bufferMin: 5,
        minBlockMin: 15,
      );
      expect(monday(settings: s), [
        b(p(2026, 11, 9, 8), p(2026, 11, 9, 12, 30)),
        b(p(2026, 11, 9, 14), p(2026, 11, 9, 19)),
      ]);
    });

    test('consecutive full days merge across midnight', () {
      expect(
        compute(p(2026, 11, 9), p(2026, 11, 11), settings: allDayEveryDay),
        [b(p(2026, 11, 9), p(2026, 11, 11))],
      );
    });

    test('multi-day range is sorted', () {
      final blocks = compute(p(2026, 11, 9), p(2026, 11, 14));
      expect(blocks, hasLength(5));
      expect(blocks.first.start, p(2026, 11, 9, 8));
      expect(blocks.last.end, p(2026, 11, 13, 19));
      for (var i = 1; i < blocks.length; i++) {
        expect(blocks[i].start.isAfter(blocks[i - 1].end), isTrue);
      }
    });
  });

  group('busy events', () {
    test('subtracted with a buffer on each side', () {
      expect(monday(events: [event(p(2026, 11, 9, 10), p(2026, 11, 9, 11))]), [
        b(p(2026, 11, 9, 8), p(2026, 11, 9, 9, 55)),
        b(p(2026, 11, 9, 11, 5), p(2026, 11, 9, 19)),
      ]);
    });

    test('non-busy (transparent) timed events are ignored', () {
      expect(
        monday(
          events: [event(p(2026, 11, 9, 10), p(2026, 11, 9, 11), busy: false)],
        ),
        [b(p(2026, 11, 9, 8), p(2026, 11, 9, 19))],
      );
    });

    test('overlapping events are merged', () {
      expect(
        monday(
          events: [
            event(p(2026, 11, 9, 10), p(2026, 11, 9, 11)),
            event(p(2026, 11, 9, 10, 30), p(2026, 11, 9, 12)),
          ],
        ),
        [
          b(p(2026, 11, 9, 8), p(2026, 11, 9, 9, 55)),
          b(p(2026, 11, 9, 12, 5), p(2026, 11, 9, 19)),
        ],
      );
    });

    test('event contained in another changes nothing', () {
      expect(
        monday(
          events: [
            event(p(2026, 11, 9, 10), p(2026, 11, 9, 12)),
            event(p(2026, 11, 9, 10, 30), p(2026, 11, 9, 11)),
          ],
        ),
        [
          b(p(2026, 11, 9, 8), p(2026, 11, 9, 9, 55)),
          b(p(2026, 11, 9, 12, 5), p(2026, 11, 9, 19)),
        ],
      );
    });

    test('gap shorter than the minimum is dropped', () {
      // 11:05–11:10 after buffers: 5 min.
      expect(
        monday(
          events: [
            event(p(2026, 11, 9, 10), p(2026, 11, 9, 11)),
            event(p(2026, 11, 9, 11, 15), p(2026, 11, 9, 12)),
          ],
        ),
        [
          b(p(2026, 11, 9, 8), p(2026, 11, 9, 9, 55)),
          b(p(2026, 11, 9, 12, 5), p(2026, 11, 9, 19)),
        ],
      );
    });

    test('gap exactly the minimum is kept', () {
      // 11:05–11:20 after buffers: 15 min.
      expect(
        monday(
          events: [
            event(p(2026, 11, 9, 10), p(2026, 11, 9, 11)),
            event(p(2026, 11, 9, 11, 25), p(2026, 11, 9, 12)),
          ],
        ),
        contains(b(p(2026, 11, 9, 11, 5), p(2026, 11, 9, 11, 20))),
      );
    });

    test('event straddling the start of the day', () {
      expect(
        monday(events: [event(p(2026, 11, 9, 7), p(2026, 11, 9, 8, 30))]),
        [b(p(2026, 11, 9, 8, 35), p(2026, 11, 9, 19))],
      );
    });

    test('buffer of an event outside working hours reaches in', () {
      expect(
        monday(
          events: [
            event(p(2026, 11, 9, 6), p(2026, 11, 9, 7, 58)),
            event(p(2026, 11, 9, 19, 2), p(2026, 11, 9, 20)),
          ],
        ),
        [b(p(2026, 11, 9, 8, 3), p(2026, 11, 9, 18, 57))],
      );
    });

    test('event covering the whole day leaves nothing', () {
      expect(
        monday(events: [event(p(2026, 11, 9, 7), p(2026, 11, 9, 20))]),
        isEmpty,
      );
    });

    test('event spanning midnight affects both days', () {
      expect(
        compute(
          p(2026, 11, 9),
          p(2026, 11, 11),
          events: [event(p(2026, 11, 9, 18), p(2026, 11, 10, 9))],
        ),
        [
          b(p(2026, 11, 9, 8), p(2026, 11, 9, 17, 55)),
          b(p(2026, 11, 10, 9, 5), p(2026, 11, 10, 19)),
        ],
      );
    });

    test('custom buffer and minimum block', () {
      final s = FreeBlockSettings(
        workingHours: defaults.workingHours,
        bufferMin: 0,
        minBlockMin: 30,
      );
      expect(
        monday(
          settings: s,
          events: [
            event(p(2026, 11, 9, 8, 20), p(2026, 11, 9, 10)),
            event(p(2026, 11, 9, 10, 30), p(2026, 11, 9, 18, 40)),
          ],
        ),
        // 08:00–08:20 (20 min) and 18:40–19:00 (20 min) dropped.
        [b(p(2026, 11, 9, 10), p(2026, 11, 9, 10, 30))],
      );
    });
  });

  group('all-day events', () {
    test('non-busy all-day events are ignored', () {
      expect(
        monday(events: [allDay(z(2026, 11, 9), z(2026, 11, 10), busy: false)]),
        [b(p(2026, 11, 9, 8), p(2026, 11, 9, 19))],
      );
    });

    test('busy all-day event blocks its whole local day', () {
      expect(
        monday(events: [allDay(z(2026, 11, 9), z(2026, 11, 10))]),
        isEmpty,
      );
    });

    test('multi-day busy all-day event, end date exclusive', () {
      expect(
        compute(
          p(2026, 11, 9),
          p(2026, 11, 12),
          events: [allDay(z(2026, 11, 9), z(2026, 11, 11))],
        ),
        [b(p(2026, 11, 11, 8), p(2026, 11, 11, 19))],
      );
    });

    test('buffer is not applied around all-day events', () {
      expect(
        compute(
          p(2026, 11, 9),
          p(2026, 11, 11),
          settings: FreeBlockSettings(
            workingHours: allDayEveryDay.workingHours,
            bufferMin: 30,
            minBlockMin: 15,
          ),
          events: [allDay(z(2026, 11, 9), z(2026, 11, 10))],
        ),
        [b(p(2026, 11, 10), p(2026, 11, 11))],
      );
    });
  });

  group('range clipping', () {
    test('blocks are clipped to the range', () {
      expect(compute(p(2026, 11, 9, 12), p(2026, 11, 9, 13)), [
        b(p(2026, 11, 9, 12), p(2026, 11, 9, 13)),
      ]);
    });

    test('clipped remainder below the minimum is dropped', () {
      expect(compute(p(2026, 11, 9, 18, 50), p(2026, 11, 10)), isEmpty);
    });

    test('empty or inverted range yields nothing', () {
      expect(compute(p(2026, 11, 9, 12), p(2026, 11, 9, 12)), isEmpty);
      expect(compute(p(2026, 11, 9, 12), p(2026, 11, 9, 8)), isEmpty);
    });

    test('a range starting mid-day still sees that day', () {
      expect(compute(p(2026, 11, 9, 10), p(2026, 11, 9, 23, 59)), [
        b(p(2026, 11, 9, 10), p(2026, 11, 9, 19)),
      ]);
    });
  });

  group('DST in Europe/Paris', () {
    // 2026: clocks go forward Sun 29 Mar 02:00 CET → 03:00 CEST,
    // and back Sun 25 Oct 03:00 CEST → 02:00 CET.

    test('working hours keep wall-clock time across spring-forward', () {
      final blocks = compute(p(2026, 3, 27), p(2026, 3, 31));
      expect(blocks, [
        b(z(2026, 3, 27, 7), z(2026, 3, 27, 18)), // Fri, UTC+1
        b(z(2026, 3, 30, 6), z(2026, 3, 30, 17)), // Mon, UTC+2
      ]);
    });

    test('working hours keep wall-clock time across fall-back', () {
      final blocks = compute(p(2026, 10, 23), p(2026, 10, 27));
      expect(blocks, [
        b(z(2026, 10, 23, 6), z(2026, 10, 23, 17)), // Fri, UTC+2
        b(z(2026, 10, 26, 7), z(2026, 10, 26, 18)), // Mon, UTC+1
      ]);
    });

    test('spring-forward day is 23 h long', () {
      final blocks = compute(
        p(2026, 3, 29),
        p(2026, 3, 30),
        settings: allDayEveryDay,
      );
      expect(blocks, [b(z(2026, 3, 28, 23), z(2026, 3, 29, 22))]);
      expect(blocks.single.length, const Duration(hours: 23));
    });

    test('fall-back day is 25 h long', () {
      final blocks = compute(
        p(2026, 10, 25),
        p(2026, 10, 26),
        settings: allDayEveryDay,
      );
      expect(blocks, [b(z(2026, 10, 24, 22), z(2026, 10, 25, 23))]);
      expect(blocks.single.length, const Duration(hours: 25));
    });

    test('window spanning the spring-forward gap loses an hour', () {
      final s = FreeBlockSettings(
        workingHours: WorkingHours({
          DateTime.sunday: [w('01:00', '04:00')],
        }),
        bufferMin: 5,
        minBlockMin: 15,
      );
      final blocks = compute(p(2026, 3, 29), p(2026, 3, 30), settings: s);
      // 01:00 CET = 00:00Z, 04:00 CEST = 02:00Z.
      expect(blocks, [b(z(2026, 3, 29, 0), z(2026, 3, 29, 2))]);
    });

    test('window spanning the fall-back overlap gains an hour', () {
      final s = FreeBlockSettings(
        workingHours: WorkingHours({
          DateTime.sunday: [w('01:00', '04:00')],
        }),
        bufferMin: 5,
        minBlockMin: 15,
      );
      final blocks = compute(p(2026, 10, 25), p(2026, 10, 26), settings: s);
      // 01:00 CEST = 23:00Z (Sat), 04:00 CET = 03:00Z.
      expect(blocks, [b(z(2026, 10, 24, 23), z(2026, 10, 25, 3))]);
    });

    test('window starting inside the spring-forward gap starts after it', () {
      final s = FreeBlockSettings(
        workingHours: WorkingHours({
          DateTime.sunday: [w('02:30', '05:00')],
        }),
        bufferMin: 5,
        minBlockMin: 15,
      );
      final blocks = compute(p(2026, 3, 29), p(2026, 3, 30), settings: s);
      // 02:30 does not exist; it resolves to 03:30 CEST = 01:30Z.
      expect(blocks, [b(z(2026, 3, 29, 1, 30), z(2026, 3, 29, 3))]);
    });

    test('UTC event across the spring-forward instant', () {
      // 00:30Z–01:30Z = 01:30 CET – 03:30 CEST.
      final blocks = compute(
        p(2026, 3, 29),
        p(2026, 3, 30),
        settings: allDayEveryDay,
        events: [event(z(2026, 3, 29, 0, 30), z(2026, 3, 29, 1, 30))],
      );
      expect(blocks, [
        b(z(2026, 3, 28, 23), z(2026, 3, 29, 0, 30)),
        b(z(2026, 3, 29, 1, 30), z(2026, 3, 29, 22)),
      ]);
    });

    test('busy all-day event on the spring-forward day blocks 23 h', () {
      final blocks = compute(
        p(2026, 3, 28),
        p(2026, 3, 31),
        settings: allDayEveryDay,
        events: [allDay(z(2026, 3, 29), z(2026, 3, 30))],
      );
      expect(blocks, [
        b(p(2026, 3, 28), z(2026, 3, 28, 23)),
        b(z(2026, 3, 29, 22), p(2026, 3, 31)),
      ]);
    });

    test('busy all-day event on the fall-back day blocks 25 h', () {
      final blocks = compute(
        p(2026, 10, 24),
        p(2026, 10, 27),
        settings: allDayEveryDay,
        events: [allDay(z(2026, 10, 25), z(2026, 10, 26))],
      );
      expect(blocks, [
        b(p(2026, 10, 24), z(2026, 10, 24, 22)),
        b(z(2026, 10, 25, 23), p(2026, 10, 27)),
      ]);
      expect(
        blocks[1].start.difference(blocks[0].end),
        const Duration(hours: 25),
      );
    });

    test('busy event keeps its wall-clock buffer across DST week', () {
      // Same 10:00–11:00 Paris meeting on Fri before and Mon after.
      final blocks = compute(
        p(2026, 3, 27),
        p(2026, 3, 31),
        events: [
          event(p(2026, 3, 27, 10), p(2026, 3, 27, 11), uid: 'fri'),
          event(p(2026, 3, 30, 10), p(2026, 3, 30, 11), uid: 'mon'),
        ],
      );
      expect(blocks, [
        b(z(2026, 3, 27, 7), z(2026, 3, 27, 8, 55)),
        b(z(2026, 3, 27, 10, 5), z(2026, 3, 27, 18)),
        b(z(2026, 3, 30, 6), z(2026, 3, 30, 7, 55)),
        b(z(2026, 3, 30, 9, 5), z(2026, 3, 30, 17)),
      ]);
    });
  });

  group('WorkingHours JSON', () {
    test('round-trips with weekday keys', () {
      final hours = WorkingHours({
        DateTime.monday: [w('08:00', '12:00'), w('14:00', '19:00')],
        DateTime.sunday: [w('10:00', '12:00')],
      });
      expect(hours.toJson(), {
        'mon': [
          {'start': '08:00', 'end': '12:00'},
          {'start': '14:00', 'end': '19:00'},
        ],
        'sun': [
          {'start': '10:00', 'end': '12:00'},
        ],
      });
      expect(WorkingHours.fromJson(hours.toJson()), hours);
    });

    test('rejects unknown day keys', () {
      expect(
        () => WorkingHours.fromJson({'monday': <Object?>[]}),
        throwsFormatException,
      );
    });

    test('settings round-trip and reject negatives', () {
      expect(FreeBlockSettings.fromJson(defaults.toJson()), defaults);
      expect(
        () => FreeBlockSettings.fromJson(defaults.toJson()..['bufferMin'] = -1),
        throwsFormatException,
      );
    });
  });
}
