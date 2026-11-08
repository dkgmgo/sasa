import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Source whose calls fail with [SourceUnavailable] when the flags say so.
final class _FlakySource implements CalendarSource {
  _FlakySource(this.inner);
  final CalendarSource inner;
  bool eventsDown = false;
  bool tasksDown = false;
  Error? otherError;
  int eventCalls = 0;
  int taskCalls = 0;

  @override
  Future<List<CalEvent>> events(DateTime from, DateTime to) async {
    eventCalls++;
    if (otherError case final e?) throw e;
    if (eventsDown) throw const SourceUnavailable('calendar permission');
    return inner.events(from, to);
  }

  @override
  Future<List<TaskItem>> tasks() async {
    taskCalls++;
    if (tasksDown) throw const SourceUnavailable('no task provider');
    return inner.tasks();
  }
}

void main() {
  final phoneEvent = event(z(2026, 11, 9, 8), z(2026, 11, 9, 9), uid: 'phone');
  final serverEvent = event(z(2026, 11, 9, 8), z(2026, 11, 9, 9), uid: 'srv');
  final phoneTask = TaskItem(
    uid: 'pt',
    title: 'Phone task',
    listName: 'PhD',
    tags: const [],
    completed: false,
  );
  final serverTask = TaskItem(
    uid: 'st',
    title: 'Server task',
    listName: 'PhD',
    tags: const [],
    completed: false,
  );

  late _FlakySource primary;
  late FakeSource fallback;
  late List<(String, SourceUnavailable)> fallbacks;
  late FallbackSource source;

  setUp(() {
    primary = _FlakySource(
      FakeSource(events: [phoneEvent], tasks: [phoneTask]),
    );
    fallback = FakeSource(events: [serverEvent], tasks: [serverTask]);
    fallbacks = [];
    source = FallbackSource(
      primary: primary,
      fallback: fallback,
      onFallback: (op, e) => fallbacks.add((op, e)),
    );
  });

  final from = z(2026, 11, 9);
  final to = z(2026, 11, 10);

  test('uses the primary source while it works', () async {
    expect(await source.events(from, to), [phoneEvent]);
    expect(await source.tasks(), [phoneTask]);
    expect(fallbacks, isEmpty);
  });

  test('falls back per call: tasks can come from CalDAV alone', () async {
    primary.tasksDown = true;
    expect(await source.events(from, to), [phoneEvent]);
    expect(await source.tasks(), [serverTask]);
    expect(fallbacks.map((f) => f.$1), ['tasks']);
    expect(fallbacks.single.$2.reason, 'no task provider');
  });

  test('falls back for events when the permission is revoked', () async {
    primary.eventsDown = true;
    expect(await source.events(from, to), [serverEvent]);
    expect(fallbacks.map((f) => f.$1), ['events']);
  });

  test(
    'retries the primary on the next call (permission re-granted)',
    () async {
      primary.eventsDown = true;
      await source.events(from, to);
      primary.eventsDown = false;
      expect(await source.events(from, to), [phoneEvent]);
      expect(primary.eventCalls, 2);
    },
  );

  test('other errors are not swallowed', () async {
    primary.otherError = StateError('bug');
    await expectLater(source.events(from, to), throwsStateError);
    expect(fallbacks, isEmpty);
  });

  test('UnavailableSource always throws SourceUnavailable', () async {
    const s = UnavailableSource('CalDAV account not configured');
    await expectLater(
      s.events(from, to),
      throwsA(
        isA<SourceUnavailable>().having(
          (e) => e.reason,
          'reason',
          'CalDAV account not configured',
        ),
      ),
    );
    await expectLater(s.tasks(), throwsA(isA<SourceUnavailable>()));
    expect(const SourceUnavailable('x').toString(), 'SourceUnavailable: x');
  });

  test('both down: the fallback error propagates', () async {
    primary.eventsDown = true;
    final s = FallbackSource(
      primary: primary,
      fallback: const UnavailableSource('CalDAV account not configured'),
    );
    await expectLater(
      s.events(from, to),
      throwsA(
        isA<SourceUnavailable>().having(
          (e) => e.reason,
          'reason',
          'CalDAV account not configured',
        ),
      ),
    );
  });
}
