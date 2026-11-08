import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sasa_core/sasa_core.dart';

import 'fake_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(DavxBridge.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;
  final bridge = DavxBridge();

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('instances sends epoch ms and parses rows', () async {
    final start = DateTime.utc(2026, 11, 9);
    final end = DateTime.utc(2026, 11, 10);
    handler = (_) async => [
      instanceRow(
        begin: DateTime.utc(2026, 11, 9, 8),
        end: DateTime.utc(2026, 11, 9, 9),
      ),
      {'title': 'no begin, skipped'},
    ];
    final rows = await bridge.instances(start, end);
    expect(calls.single.method, 'instances');
    expect(calls.single.arguments, {'start': ms(start), 'end': ms(end)});
    expect(rows, hasLength(1));
    expect(rows.single.uid, 'uid-1');
  });

  test('status, calendars and tasks decode', () async {
    handler = (call) async => switch (call.method) {
      'status' => {
        'calendarPermission': true,
        'taskAuthority': 'org.tasks.opentasks',
        'taskPermission': true,
      },
      'calendars' => [
        {'_id': 1, 'account_type': 'bitfire.at.davdroid'},
      ],
      'tasks' => {
        'authority': 'org.tasks.opentasks',
        'tasks': [taskRow()],
        'categories': <Object?>[],
      },
      _ => null,
    };
    expect((await bridge.status()).taskPermission, isTrue);
    expect((await bridge.calendars()).single.isDavx, isTrue);
    expect((await bridge.tasks()).tasks.single.uid, 'task-1');
  });

  test('requestPermissions passes which permissions to ask for', () async {
    handler = (_) async => {'calendarPermission': true, 'prompted': true};
    final s = await bridge.requestPermissions(tasks: false);
    expect(calls.single.arguments, {'calendar': true, 'tasks': false});
    expect(s.prompted, isTrue);
  });

  test('permission and provider errors become SourceUnavailable', () async {
    for (final code in DavxBridge.unavailableCodes) {
      handler = (_) async => throw PlatformException(code: code, message: 'x');
      await expectLater(
        bridge.tasks(),
        throwsA(
          isA<SourceUnavailable>().having(
            (e) => e.reason,
            'reason',
            '$code: x',
          ),
        ),
      );
    }
  });

  test('other platform errors are rethrown', () async {
    handler = (_) async => throw PlatformException(code: 'query_failed');
    await expectLater(bridge.calendars(), throwsA(isA<PlatformException>()));
  });

  test('no plugin (e.g. Linux) becomes SourceUnavailable', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(bridge.status(), throwsA(isA<SourceUnavailable>()));
  });

  test('null replies decode as empty', () async {
    handler = (_) async => null;
    expect((await bridge.status()).calendarPermission, isFalse);
    expect(await bridge.calendars(), isEmpty);
    expect((await bridge.tasks()).tasks, isEmpty);
  });
}
