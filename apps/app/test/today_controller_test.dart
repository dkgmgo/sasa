import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/src/data_controller.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa/src/source_controller.dart';
import 'package:sasa/src/today_controller.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'fakes.dart';

final paris = locationFor('Europe/Paris');

DateTime p(int d, int h, [int m = 0]) =>
    utcInstant(tz.TZDateTime(paris, 2026, 11, d, h, m));

/// A source that counts calls and can fail.
final class CountingSource implements CalendarSource {
  CountingSource(this.inner);
  final FakeSource inner;
  int eventCalls = 0;
  int taskCalls = 0;
  Object? taskError;
  (DateTime, DateTime)? lastRange;

  @override
  Future<List<CalEvent>> events(DateTime from, DateTime to) {
    eventCalls++;
    lastRange = (from, to);
    return inner.events(from, to);
  }

  @override
  Future<List<TaskItem>> tasks() {
    taskCalls++;
    if (taskError case final e?) return Future.error(e);
    return inner.tasks();
  }
}

void main() {
  late FakeClock clock;
  late CountingSource source;
  late DataController data;
  late SourceController sources;
  late TodayController today;

  setUp(() async {
    clock = FakeClock(p(9, 10, 30));
    source = CountingSource(
      FakeSource(
        events: [
          CalEvent(
            uid: 'lecture',
            title: 'Lecture',
            start: p(9, 14),
            end: p(9, 16),
            allDay: false,
            busy: true,
            calendarName: 'Cours',
          ),
        ],
        tasks: [
          TaskItem(
            uid: 't',
            title: 'Review',
            listName: 'PhD',
            tags: const [],
            due: p(9, 18),
            completed: false,
          ),
        ],
      ),
    );
    final settings = MemoryDeviceSettings(syncFolder: syncA, setupDone: true);
    data = DataController(
      settings: settings,
      access: MemoryFolderAccess(),
      clock: clock,
    );
    sources = SourceController(
      platform: SourcePlatform.linux,
      settings: settings,
      bridge: FakeBridge(),
      zone: paris,
      calDav: () async => source,
      // Each refresh returns whatever [source] is now.
    );
    today = TodayController(
      data: data,
      sources: sources,
      clock: clock,
      fallbackZone: paris,
    );
    await data.openSaved();
    await sources.refresh();
    await today.refresh();
  });

  test('loads today and the inbox range from the source', () {
    expect(source.lastRange, (p(9, 0), p(9 + inboxLookaheadDays, 0)));
    final view = today.today!;
    expect(view.timeline.whereType<EventEntry>().single.event.uid, 'lecture');
    expect(view.dueTasks.single.task.uid, 't');
    expect(today.inbox!.itemCount, 2);
    expect(today.eventsError, isNull);
  });

  test('a config change rebuilds without fetching again', () async {
    final calls = source.eventCalls;
    await data.updateConfig(
      ConfigEdits.addRule(
        const MappingRule(
          field: MatchField.calendar,
          pattern: 'Cours',
          categoryId: 'teaching',
        ),
      ),
    );
    expect(source.eventCalls, calls);
    expect(
      today.today!.timeline.whereType<EventEntry>().single.category?.id,
      'teaching',
    );
    expect(today.inbox!.itemCount, 1);
  });

  test('a new source is fetched automatically, the same one is not', () async {
    final old = source;
    final calls = old.eventCalls;
    await sources.refresh();
    await pumpEventQueue();
    expect(old.eventCalls, calls);

    source = CountingSource(old.inner);
    await sources.refresh();
    await pumpEventQueue();
    expect(source.eventCalls, 1);
    expect(old.eventCalls, calls);
  });

  test('tick moves now; a new day fetches again', () async {
    final calls = source.eventCalls;
    clock.advance(const Duration(hours: 6));
    await today.tick();
    expect(source.eventCalls, calls);
    expect(
      today.today!.timeline.whereType<EventEntry>().single.status,
      TimeStatus.past,
    );
    clock.set(p(10, 8));
    await today.tick();
    expect(source.eventCalls, calls + 1);
    expect(today.today!.window.date, DateTime.utc(2026, 11, 10));
  });

  test('a failing task source keeps the events', () async {
    source.taskError = const SourceUnavailable('CalDAV account not configured');
    await today.refresh();
    expect(today.tasksError, contains('No CalDAV account'));
    expect(today.eventsError, isNull);
    expect(today.today!.timeline.whereType<EventEntry>(), hasLength(1));
    expect(today.today!.dueTasks, isEmpty);
  });

  test('other errors are shown too', () async {
    source.taskError = Exception('boom');
    await today.refresh();
    expect(today.tasksError, contains('boom'));
  });
}
