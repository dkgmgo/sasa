import 'dart:math';

import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

var _seq = 0;

/// Builds an event at [ts] from [device] (ids are unique per call).
LogEvent ev(
  DateTime ts,
  EventPayload p, {
  String device = 'linux-1',
  String? id,
  int v = eventSchemaVersion,
}) => LogEvent(
  id: id ?? 'e${_seq++}',
  ts: ts,
  device: device,
  type: p.type,
  v: v,
  data: p.toJson(),
);

SessionStarted started(String id, DateTime start, {String cat = 'research'}) =>
    SessionStarted(
      sessionId: id,
      activityId: 'act-$id',
      categoryId: cat,
      plannedMin: 60,
      start: start,
    );

SessionCompleted completed(
  String id,
  DateTime start,
  DateTime end, {
  String cat = 'research',
}) => SessionCompleted(
  sessionId: id,
  activityId: 'act-$id',
  categoryId: cat,
  start: start,
  end: end,
);

void main() {
  final t0 = z(2026, 11, 8, 9);

  test('empty log gives an empty state', () {
    final s = AppState.fold(const []);
    expect(s, AppState.empty);
    expect(s.sessions, isEmpty);
    expect(s.activeSessions, isEmpty);
    expect(s.eventCount, 0);
    expect(s.lastEventAt, isNull);
    expect(s.latestEnergy, isNull);
  });

  group('sessions', () {
    test('started is active until completed', () {
      final start = ev(t0, started('s1', t0));
      final s1 = AppState.fold([start]);
      expect(s1.activeSessions.keys, ['s1']);
      expect(s1.activeSessions['s1']!.plannedMin, 60);
      expect(s1.activeSessions['s1']!.device, 'linux-1');

      final end = t0.add(const Duration(minutes: 50));
      final s2 = AppState.fold([start, ev(end, completed('s1', t0, end))]);
      expect(s2.activeSessions, isEmpty);
      expect(s2.sessions, [
        FocusSession(
          id: 's1',
          activityId: 'act-s1',
          categoryId: 'research',
          start: t0,
          end: end,
          completed: true,
        ),
      ]);
    });

    test('abandoned sessions are kept with completed = false', () {
      final end = t0.add(const Duration(minutes: 5));
      final s = AppState.fold([
        ev(t0, started('s1', t0)),
        ev(
          end,
          SessionAbandoned(
            sessionId: 's1',
            activityId: 'act-s1',
            categoryId: 'research',
            start: t0,
            end: end,
            note: 'phone call',
          ),
        ),
      ]);
      expect(s.sessions.single.completed, isFalse);
      expect(s.sessions.single.note, 'phone call');
      expect(s.activeSessions, isEmpty);
    });

    test('an end that sorts before its start (clock skew) still wins', () {
      final end = t0.add(const Duration(minutes: 30));
      // The phone's clock was behind: its "completed" is stamped earlier
      // than the laptop's "started".
      final s = AppState.fold([
        ev(t0.add(const Duration(minutes: 1)), started('s1', t0)),
        ev(t0, completed('s1', t0, end), device: 'android-1'),
      ]);
      expect(s.activeSessions, isEmpty);
      expect(s.sessions.single.id, 's1');
    });

    test('sessions are listed by start time', () {
      final a = z(2026, 11, 8, 14);
      final b = z(2026, 11, 8, 9);
      final s = AppState.fold([
        ev(
          a.add(const Duration(hours: 1)),
          completed('late', a, a.add(const Duration(hours: 1))),
        ),
        ev(
          b.add(const Duration(hours: 1)),
          completed('early', b, b.add(const Duration(hours: 1))),
        ),
      ]);
      expect(s.sessions.map((x) => x.id), ['early', 'late']);
    });

    test('a session ended twice keeps the first end', () {
      final e1 = t0.add(const Duration(minutes: 30));
      final e2 = t0.add(const Duration(minutes: 45));
      final s = AppState.fold([
        ev(e1, completed('s1', t0, e1)),
        ev(e2, completed('s1', t0, e2), device: 'android-1'),
      ]);
      expect(s.sessions.single.end, e1);
    });
  });

  group('suggestions', () {
    test('shown and skipped are recorded; skips counted per activity', () {
      const skip = SuggestionSkipped(activityId: 'a1', categoryId: 'reading');
      final s = AppState.fold([
        ev(z(2026, 11, 7, 8), skip),
        ev(z(2026, 11, 8, 8), skip),
        ev(z(2026, 11, 8, 9), skip),
        ev(
          z(2026, 11, 8, 9),
          const SuggestionSkipped(activityId: 'a2', categoryId: 'reading'),
        ),
        ev(
          z(2026, 11, 8, 9),
          const SuggestionShown(activityId: 'a1', categoryId: 'reading'),
        ),
      ]);
      expect(s.shown, hasLength(1));
      expect(s.skips, hasLength(4));
      final since = z(2026, 11, 8, 10).subtract(const Duration(hours: 24));
      expect(s.skipsOf('a1', since: since), 2);
      expect(s.skipsOf('a2', since: since), 1);
      expect(s.skipsOf('a3', since: since), 0);
    });
  });

  group('nudges', () {
    test('tracks last fired, dismissed and snoozed', () {
      final s = AppState.fold([
        ev(z(2026, 11, 7, 9), const NudgeFired(nudgeId: 'n')),
        ev(z(2026, 11, 8, 9), const NudgeFired(nudgeId: 'n')),
        ev(z(2026, 11, 8, 9, 5), const NudgeDismissed(nudgeId: 'n')),
        ev(
          z(2026, 11, 8, 9, 6),
          NudgeSnoozed(nudgeId: 'n', until: z(2026, 11, 8, 14)),
        ),
      ]);
      expect(
        s.nudges['n'],
        NudgeState(
          lastFired: z(2026, 11, 8, 9),
          lastDismissed: z(2026, 11, 8, 9, 5),
          snoozedUntil: z(2026, 11, 8, 14),
        ),
      );
      expect(s.nudges['other'], isNull);
    });
  });

  test('teaching prep is keyed by event uid and occurrence start', () {
    final s = AppState.fold([
      ev(t0, TeachingPrepared(eventUid: 'tp', eventStart: z(2026, 11, 10, 9))),
    ]);
    expect(s.isTeachingPrepared('tp', z(2026, 11, 10, 9)), isTrue);
    expect(s.isTeachingPrepared('tp', z(2026, 11, 17, 9)), isFalse);
    expect(s.isTeachingPrepared('other', z(2026, 11, 10, 9)), isFalse);
  });

  group('papers', () {
    const add = PaperAdded(
      paperId: 'p1',
      title: 'Paper',
      arxivId: '2601.00001',
      source: 'arxiv',
    );

    test('added papers start as to-read; status changes apply', () {
      final s = AppState.fold([
        ev(t0, add),
        ev(
          t0.add(const Duration(days: 1)),
          const PaperStatusChanged(paperId: 'p1', status: PaperStatus.reading),
        ),
        ev(
          t0.add(const Duration(days: 2)),
          const PaperStatusChanged(
            paperId: 'p1',
            status: PaperStatus.read,
            note: 'cite in ch.2',
          ),
        ),
      ]);
      final p = s.papers['p1']!;
      expect(p.title, 'Paper');
      expect(p.arxivId, '2601.00001');
      expect(p.status, PaperStatus.read);
      expect(p.note, 'cite in ch.2');
      expect(p.addedAt, t0);
      expect(p.statusChangedAt, t0.add(const Duration(days: 2)));
    });

    test('a status change stamped before the add is applied after it', () {
      final s = AppState.fold([
        ev(
          t0.subtract(const Duration(minutes: 1)),
          const PaperStatusChanged(paperId: 'p1', status: PaperStatus.reading),
          device: 'android-1',
        ),
        ev(t0, add),
      ]);
      expect(s.papers['p1']!.status, PaperStatus.reading);
    });

    test('adding the same paper again keeps the first record', () {
      final s = AppState.fold([
        ev(t0, add),
        ev(
          t0.add(const Duration(hours: 1)),
          const PaperStatusChanged(paperId: 'p1', status: PaperStatus.read),
        ),
        ev(
          t0.add(const Duration(hours: 2)),
          const PaperAdded(paperId: 'p1', title: 'Again', source: 'manual'),
        ),
      ]);
      expect(s.papers['p1']!.title, 'Paper');
      expect(s.papers['p1']!.status, PaperStatus.read);
    });

    test('a status change for a paper never added is not a paper', () {
      final s = AppState.fold([
        ev(
          t0,
          const PaperStatusChanged(paperId: 'ghost', status: PaperStatus.read),
        ),
      ]);
      expect(s.papers, isEmpty);
    });
  });

  group('deadlines', () {
    final add = DeadlineAdded(
      deadlineId: 'd1',
      title: 'Chapter 2',
      due: z(2026, 12, 15),
      hoursLeft: 40,
      categoryId: 'writing',
    );

    test('updates change only the given fields', () {
      final s = AppState.fold([
        ev(t0, add),
        ev(
          t0.add(const Duration(days: 1)),
          const DeadlineUpdated(deadlineId: 'd1', hoursLeft: 30),
        ),
        ev(
          t0.add(const Duration(days: 2)),
          DeadlineUpdated(deadlineId: 'd1', due: z(2026, 12, 20)),
        ),
      ]);
      final d = s.deadlines['d1']!;
      expect(d.title, 'Chapter 2');
      expect(d.hoursLeft, 30);
      expect(d.due, z(2026, 12, 20));
      expect(d.done, isFalse);
      expect(d.updatedAt, t0.add(const Duration(days: 2)));
    });

    test('an update stamped before the add is applied after it', () {
      final s = AppState.fold([
        ev(
          t0.subtract(const Duration(minutes: 1)),
          const DeadlineUpdated(deadlineId: 'd1', done: true),
          device: 'android-1',
        ),
        ev(t0, add),
      ]);
      expect(s.deadlines['d1']!.done, isTrue);
    });
  });

  test('latest energy check-in wins', () {
    final s = AppState.fold([
      ev(z(2026, 11, 8, 8), const EnergyCheckin(energy: Energy.high)),
      ev(z(2026, 11, 8, 15), const EnergyCheckin(energy: Energy.low)),
    ]);
    expect(s.energy, hasLength(2));
    expect(s.latestEnergy, EnergyRecord(z(2026, 11, 8, 15), Energy.low));
  });

  group('tolerance', () {
    test('duplicate event ids are applied once', () {
      final skip = ev(
        t0,
        const SuggestionSkipped(activityId: 'a', categoryId: 'c'),
        id: 'same',
      );
      final s = AppState.fold([skip, skip, skip]);
      expect(s.skips, hasLength(1));
      expect(s.eventCount, 1);
    });

    test('unknown types, newer versions and bad data are skipped', () {
      final skipped = <String>[];
      final s = AppState.fold([
        LogEvent(
          id: 'u',
          ts: t0,
          device: 'd',
          type: 'future.thing',
          v: 1,
          data: const {},
        ),
        ev(t0, const EnergyCheckin(energy: Energy.low), v: 99, id: 'newer'),
        LogEvent(
          id: 'bad',
          ts: t0,
          device: 'd',
          type: 'energy.checkin',
          v: 1,
          data: const {'energy': 'sleepy'},
        ),
        ev(t0, const EnergyCheckin(energy: Energy.medium), id: 'ok'),
      ], onSkipped: (e, _) => skipped.add(e.id));
      expect(skipped, unorderedEquals(['newer', 'bad']));
      expect(s.latestEnergy!.energy, Energy.medium);
      expect(s.eventCount, 4, reason: 'every distinct event counts as seen');
    });

    test('result does not depend on input order', () {
      final events = <LogEvent>[
        for (var i = 0; i < 20; i++) ...[
          ev(
            t0.add(Duration(hours: i)),
            started('s$i', t0.add(Duration(hours: i))),
            device: i.isEven ? 'linux-1' : 'android-1',
          ),
          if (i % 3 != 0)
            ev(
              t0.add(Duration(hours: i, minutes: 30)),
              completed(
                's$i',
                t0.add(Duration(hours: i)),
                t0.add(Duration(hours: i, minutes: 30)),
              ),
            ),
          ev(
            t0.add(Duration(hours: i)),
            SuggestionSkipped(activityId: 'a${i % 4}', categoryId: 'c'),
            device: i.isEven ? 'android-1' : 'linux-1',
          ),
          ev(
            t0.add(Duration(hours: i)),
            EnergyCheckin(energy: Energy.values[i % 3]),
            device: i.isEven ? 'android-1' : 'linux-1',
          ),
        ],
      ];
      final reference = AppState.fold(events);
      final r = Random(42);
      for (var k = 0; k < 10; k++) {
        expect(AppState.fold(List.of(events)..shuffle(r)), reference);
      }
      expect(
        reference.lastEventAt,
        t0.add(const Duration(hours: 19, minutes: 30)),
      );
    });

    test('state collections cannot be modified', () {
      final end = t0.add(const Duration(hours: 1));
      final s = AppState.fold([
        ev(t0, started('s1', t0)),
        ev(end, completed('s2', t0, end)),
      ]);
      expect(() => s.sessions.add(s.sessions.first), throwsUnsupportedError);
      expect(s.activeSessions.clear, throwsUnsupportedError);
      expect(s.papers.clear, throwsUnsupportedError);
    });
  });
}
