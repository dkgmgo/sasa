import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

LogEvent envelope(EventPayload p) => LogEvent(
  id: 'id',
  ts: z(2026, 11, 8, 9),
  device: 'd',
  type: p.type,
  v: eventSchemaVersion,
  data: p.toJson(),
);

void main() {
  final samples = <EventPayload>[
    SessionStarted(
      sessionId: 's1',
      activityId: 'a1',
      categoryId: 'research',
      plannedMin: 90,
      start: z(2026, 11, 8, 9),
    ),
    SessionCompleted(
      sessionId: 's1',
      activityId: 'a1',
      categoryId: 'research',
      start: z(2026, 11, 8, 9),
      end: z(2026, 11, 8, 10, 30),
      note: 'drafted §2',
    ),
    SessionAbandoned(
      sessionId: 's2',
      activityId: 'a2',
      categoryId: 'reading',
      start: z(2026, 11, 8, 11),
      end: z(2026, 11, 8, 11, 5),
    ),
    const SuggestionShown(
      activityId: 'a1',
      categoryId: 'research',
      freeMin: 120,
    ),
    const SuggestionSkipped(activityId: 'a1', categoryId: 'research'),
    const NudgeFired(nudgeId: 'read-paper'),
    const NudgeDismissed(nudgeId: 'read-paper'),
    NudgeSnoozed(nudgeId: 'read-paper', until: z(2026, 11, 8, 14)),
    TeachingPrepared(eventUid: 'tp-sockets', eventStart: z(2026, 11, 10, 9)),
    const PaperAdded(
      paperId: 'doi:10.1145/1234',
      title: 'A paper',
      doi: '10.1145/1234',
      source: 'zotero',
    ),
    const PaperStatusChanged(
      paperId: 'doi:10.1145/1234',
      status: PaperStatus.read,
      note: 'good related work',
    ),
    DeadlineAdded(
      deadlineId: 'thesis-ch2',
      title: 'Chapter 2',
      due: z(2026, 12, 15),
      hoursLeft: 40,
      categoryId: 'writing',
    ),
    const DeadlineUpdated(deadlineId: 'thesis-ch2', hoursLeft: 32.5),
    const EnergyCheckin(energy: Energy.high),
  ];

  test('covers every documented event type', () {
    expect(samples.map((s) => s.type).toSet(), {
      'session.started',
      'session.completed',
      'session.abandoned',
      'suggestion.shown',
      'suggestion.skipped',
      'nudge.fired',
      'nudge.dismissed',
      'nudge.snoozed',
      'teaching.prepared',
      'paper.added',
      'paper.status_changed',
      'deadline.added',
      'deadline.updated',
      'energy.checkin',
    });
    expect(knownEventTypes, samples.map((s) => s.type).toSet());
  });

  for (final s in samples) {
    test('${s.type} round-trips through a log line', () {
      final line = envelope(s).toLine();
      expect(decodePayload(LogEvent.fromLine(line)), s);
    });
  }

  test('optional fields are omitted from the JSON', () {
    expect(const SuggestionSkipped(activityId: 'a', categoryId: 'c').toJson(), {
      'activityId': 'a',
      'categoryId': 'c',
    });
    expect(const DeadlineUpdated(deadlineId: 'd', done: true).toJson(), {
      'deadlineId': 'd',
      'done': true,
    });
  });

  test('an unknown type decodes as UnknownEvent and keeps its data', () {
    final e = LogEvent(
      id: 'id',
      ts: z(2026, 1, 1),
      device: 'd',
      type: 'future.thing',
      v: 1,
      data: const {'x': 1},
    );
    expect(decodePayload(e), const UnknownEvent('future.thing', {'x': 1}));
  });

  test('a known type with bad data is a FormatException', () {
    LogEvent bad(String type, Map<String, Object?> data) => LogEvent(
      id: 'id',
      ts: z(2026, 1, 1),
      device: 'd',
      type: type,
      v: 1,
      data: data,
    );
    expect(
      () => decodePayload(bad('energy.checkin', {'energy': 'sleepy'})),
      throwsFormatException,
    );
    expect(
      () => decodePayload(bad('session.started', {'sessionId': 's'})),
      throwsFormatException,
    );
    expect(
      () => decodePayload(
        bad('session.completed', {
          'sessionId': 's',
          'activityId': 'a',
          'categoryId': 'c',
          'start': '2026-01-01T10:00:00Z',
          'end': '2026-01-01T09:00:00Z',
        }),
      ),
      throwsFormatException,
      reason: 'end before start',
    );
  });

  test('ending a session before it started is rejected when writing too', () {
    expect(
      () => SessionCompleted(
        sessionId: 's',
        activityId: 'a',
        categoryId: 'c',
        start: z(2026, 1, 1, 10),
        end: z(2026, 1, 1, 9),
      ),
      throwsArgumentError,
    );
  });

  test('newer and older schema versions', () {
    final e = envelope(const EnergyCheckin(energy: Energy.low));
    expect(isSupportedVersion(e), isTrue);
    final newer = LogEvent(
      id: e.id,
      ts: e.ts,
      device: e.device,
      type: e.type,
      v: eventSchemaVersion + 1,
      data: e.data,
    );
    expect(isSupportedVersion(newer), isFalse);
    expect(() => decodePayload(newer), throwsA(isA<UnsupportedEventVersion>()));
  });
}
