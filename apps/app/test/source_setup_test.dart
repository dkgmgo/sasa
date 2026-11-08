import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa/src/source_setup.dart';
import 'package:sasa_core/sasa_core.dart';

import 'fakes.dart';

void main() {
  final zone = locationFor('Europe/Paris');
  final from = DateTime.utc(2026, 11, 9);
  final to = DateTime.utc(2026, 11, 10);
  final serverTask = TaskItem(
    uid: 'server-task',
    title: 'Server task',
    listName: 'PhD',
    tags: const [],
    completed: false,
  );
  final server = FakeSource(
    events: [
      CalEvent(
        uid: 'server',
        title: 'Server event',
        start: DateTime.utc(2026, 11, 9, 9),
        end: DateTime.utc(2026, 11, 9, 10),
        allDay: false,
        busy: true,
        calendarName: 'PhD',
      ),
    ],
    tasks: [serverTask],
  );

  Future<SourceSetup> setUp({
    SourcePlatform platform = SourcePlatform.android,
    bool force = false,
    FakeBridge? bridge,
    CalendarSource? calDav,
    FallbackHandler? onFallback,
  }) => setUpSource(
    platform: platform,
    settings: MemoryDeviceSettings(forceCalDav: force),
    bridge: bridge ?? FakeBridge(),
    zone: zone,
    calDav: calDav,
    onFallback: onFallback,
  );

  test('Android with DAVx⁵ reads the provider', () async {
    final s = await setUp(calDav: server);
    expect(s.decision.kind, SourceKind.davxProvider);
    expect((await s.source.events(from, to)).single.uid, 'phone');
    expect((await s.source.tasks()).single.uid, 'phone-task');
    expect(s.status?.taskPermission, isTrue);
  });

  test('forced CalDAV uses the server', () async {
    final s = await setUp(force: true, calDav: server);
    expect(s.decision.reason, SourceReason.forcedInSettings);
    expect((await s.source.events(from, to)).single.uid, 'server');
    expect(s.status, isNotNull, reason: 'settings still show permissions');
  });

  test('denied calendar permission falls back to CalDAV', () async {
    final s = await setUp(
      bridge: FakeBridge(calendarPermission: false),
      calDav: server,
    );
    expect(s.decision.reason, SourceReason.calendarPermissionDenied);
    expect((await s.source.tasks()).single, serverTask);
  });

  test('missing Tasks.org: events from phone, tasks from CalDAV', () async {
    final fallbacks = <String>[];
    final s = await setUp(
      bridge: FakeBridge(taskAuthority: null),
      calDav: server,
      onFallback: (op, _) => fallbacks.add(op),
    );
    expect(s.decision.kind, SourceKind.davxProvider);
    expect((await s.source.events(from, to)).single.uid, 'phone');
    expect((await s.source.tasks()).single, serverTask);
    expect(fallbacks, ['tasks']);
  });

  test('permission revoked after selection falls back per call', () async {
    final bridge = FakeBridge();
    final s = await setUp(bridge: bridge, calDav: server);
    bridge.calendarPermission = false;
    expect((await s.source.events(from, to)).single.uid, 'server');
  });

  test('no CalDAV account: fallback reports it is not configured', () async {
    final s = await setUp(bridge: FakeBridge(calendarPermission: false));
    await expectLater(
      s.source.events(from, to),
      throwsA(
        isA<SourceUnavailable>().having(
          (e) => e.reason,
          'reason',
          calDavNotConfigured,
        ),
      ),
    );
  });

  test('Linux never touches the bridge', () async {
    final bridge = FakeBridge();
    final s = await setUp(
      platform: SourcePlatform.linux,
      bridge: bridge,
      calDav: server,
    );
    expect(s.decision.kind, SourceKind.calDav);
    expect(s.status, isNull);
    expect(bridge.statusCalls, 0);
  });
}
