import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sasa_core/sasa_core.dart';

import 'fake_bridge.dart';

void main() {
  final paris = locationFor('Europe/Paris');
  late FakeBridge bridge;
  late DavxProviderSource source;

  final from = DateTime.utc(2026, 11, 9);
  final to = DateTime.utc(2026, 11, 10);

  setUp(() {
    bridge = FakeBridge();
    source = DavxProviderSource(bridge: bridge, zone: paris);
  });

  group('events', () {
    test(
      'DAVx⁵ instances in range, sorted, cancelled/hidden dropped',
      () async {
        bridge.instanceRows = [
          instanceRow(
            uid: 'late',
            begin: DateTime.utc(2026, 11, 9, 14),
            end: DateTime.utc(2026, 11, 9, 15),
          ),
          instanceRow(
            uid: 'early',
            begin: DateTime.utc(2026, 11, 9, 8),
            end: DateTime.utc(2026, 11, 9, 9),
          ),
          instanceRow(
            uid: 'cancelled',
            begin: DateTime.utc(2026, 11, 9, 10),
            end: DateTime.utc(2026, 11, 9, 11),
            status: ProviderInstance.statusCancelled,
          ),
          instanceRow(
            uid: 'hidden',
            begin: DateTime.utc(2026, 11, 9, 10),
            end: DateTime.utc(2026, 11, 9, 11),
            visible: 0,
          ),
          instanceRow(
            uid: 'holidays',
            begin: DateTime.utc(2026, 11, 9, 10),
            end: DateTime.utc(2026, 11, 9, 11),
            accountType: 'com.google',
          ),
          // Returned by the widened device query but outside the range.
          instanceRow(
            uid: 'yesterday',
            begin: DateTime.utc(2026, 11, 8, 10),
            end: DateTime.utc(2026, 11, 8, 11),
          ),
        ];
        final events = await source.events(from, to);
        expect(events.map((e) => e.uid), ['early', 'late']);
        expect(bridge.instanceCalls, [(from, to)]);
      },
    );

    test('managed DAVx⁵ accounts count too', () async {
      bridge.instanceRows = [
        instanceRow(
          begin: DateTime.utc(2026, 11, 9, 8),
          end: DateTime.utc(2026, 11, 9, 9),
          accountType: 'com.davdroid',
        ),
      ];
      expect(await source.events(from, to), hasLength(1));
    });

    test('includeAllCalendars keeps other accounts', () async {
      bridge.instanceRows = [
        instanceRow(
          begin: DateTime.utc(2026, 11, 9, 8),
          end: DateTime.utc(2026, 11, 9, 9),
          accountType: 'LOCAL',
        ),
      ];
      final all = DavxProviderSource(
        bridge: bridge,
        zone: paris,
        includeAllCalendars: true,
      );
      expect(await all.events(from, to), hasLength(1));
      expect(await source.events(from, to), isEmpty);
    });

    test('all-day instance filtered by the local day', () async {
      // Range = 9 Nov in Paris (8 Nov 23:00Z → 9 Nov 23:00Z).
      final dayFrom = DateTime.utc(2026, 11, 8, 23);
      final dayTo = DateTime.utc(2026, 11, 9, 23);
      bridge.instanceRows = [
        for (final d in [8, 9, 10])
          instanceRow(
            uid: 'day$d',
            begin: DateTime.utc(2026, 11, d),
            end: DateTime.utc(2026, 11, d + 1),
            allDay: 1,
          ),
      ];
      expect((await source.events(dayFrom, dayTo)).map((e) => e.uid), ['day9']);
    });

    test('permission denied surfaces as SourceUnavailable', () async {
      bridge.unavailable.add('instances');
      await expectLater(
        source.events(from, to),
        throwsA(isA<SourceUnavailable>()),
      );
    });
  });

  group('tasks', () {
    test(
      'DAVx⁵ tasks with tags; overrides and other accounts dropped',
      () async {
        bridge.taskResult = {
          'authority': 'org.tasks.opentasks',
          'tasks': [
            taskRow(id: 1, uid: 'a', title: 'Read paper'),
            taskRow(id: 2, uid: 'b', status: ProviderTask.statusCompleted),
            taskRow(id: 3, uid: 'a', overrideOf: 'a'),
            taskRow(id: 4, uid: 'local', accountType: 'org.dmfs.account.LOCAL'),
          ],
          'categories': [
            {'task_id': 1, 'data1': 'reading'},
            {'task_id': 4, 'data1': 'ignored'},
          ],
        };
        final tasks = await source.tasks();
        expect(tasks.map((t) => t.uid), ['a', 'b']);
        expect(tasks[0].tags, ['reading']);
        expect(tasks[1].completed, isTrue);
        expect(tasks[1].tags, isEmpty);
      },
    );

    test('missing provider surfaces as SourceUnavailable', () async {
      bridge.unavailable.add('tasks');
      await expectLater(source.tasks(), throwsA(isA<SourceUnavailable>()));
    });
  });

  group('probe', () {
    test('counts DAVx⁵ calendars when permitted', () async {
      bridge.calendarRows = [
        {'_id': 1, 'account_type': 'bitfire.at.davdroid'},
        {'_id': 2, 'account_type': 'bitfire.at.davdroid'},
        {'_id': 3, 'account_type': 'LOCAL'},
      ];
      final p = await source.probe();
      expect(p.calendarPermission, isTrue);
      expect(p.davxCalendars, 2);
    });

    test('does not query calendars without permission', () async {
      bridge.statusValue = const BridgeStatus(
        calendarPermission: false,
        taskAuthority: null,
        taskPermission: false,
      );
      bridge.unavailable.add('calendars');
      final p = await source.probe();
      expect(p.calendarPermission, isFalse);
      expect(p.davxCalendars, 0);
    });
  });

  test('works with FallbackSource: tasks from CalDAV when denied', () async {
    bridge.instanceRows = [
      instanceRow(
        begin: DateTime.utc(2026, 11, 9, 8),
        end: DateTime.utc(2026, 11, 9, 9),
      ),
    ];
    bridge.unavailable.add('tasks');
    final serverTask = TaskItem(
      uid: 'srv',
      title: 'From server',
      listName: 'PhD',
      tags: const [],
      completed: false,
    );
    final s = FallbackSource(
      primary: source,
      fallback: FakeSource(tasks: [serverTask]),
    );
    expect(await s.events(from, to), hasLength(1));
    expect(await s.tasks(), [serverTask]);
  });
}
