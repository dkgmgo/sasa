import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_bridge.dart';

void main() {
  test('BridgeStatus reads flags and tolerates missing keys', () {
    final s = BridgeStatus.fromMap({
      'calendarPermission': true,
      'taskAuthority': 'org.tasks.opentasks',
      'taskPermission': false,
      'prompted': true,
    });
    expect(s.calendarPermission, isTrue);
    expect(s.taskAuthority, 'org.tasks.opentasks');
    expect(s.taskPermission, isFalse);
    expect(s.prompted, isTrue);
    expect(s.toString(), contains('org.tasks.opentasks'));

    final empty = BridgeStatus.fromMap(const {});
    expect(empty.calendarPermission, isFalse);
    expect(empty.taskAuthority, isNull);
  });

  test('ProviderCalendar recognises DAVx⁵ accounts', () {
    final c = ProviderCalendar.fromMap({
      '_id': 4,
      'calendar_displayName': 'PhD',
      'account_name': 'test',
      'account_type': 'bitfire.at.davdroid',
      'visible': 1,
      'sync_events': 0,
    });
    expect(c.id, 4);
    expect(c.isDavx, isTrue);
    expect(c.syncEvents, isFalse);
    expect(
      ProviderCalendar.fromMap({'account_type': 'com.davdroid'}).isDavx,
      isTrue,
    );
    expect(ProviderCalendar.fromMap({'account_type': 'LOCAL'}).isDavx, isFalse);
    expect(ProviderCalendar.fromMap(const {}).isDavx, isFalse);
  });

  test('ProviderInstance parses a row; missing begin is an error', () {
    final i = ProviderInstance.fromMap(
      instanceRow(
        begin: DateTime.utc(2026, 11, 9, 8),
        end: DateTime.utc(2026, 11, 9, 9),
        location: '  ',
      ),
    );
    expect(i.beginMs, ms(DateTime.utc(2026, 11, 9, 8)));
    expect(i.allDay, isFalse);
    expect(i.location, isNull, reason: 'blank strings count as unset');
    expect(i.visible, isTrue);
    expect(
      () => ProviderInstance.fromMap({'title': 'x'}),
      throwsFormatException,
    );
  });

  test('values of unexpected types are coerced or ignored', () {
    final i = ProviderInstance.fromMap({
      'begin': '1000',
      'end': 2000.0,
      'allDay': true,
      'visible': '0',
      'availability': 'busy?',
    });
    expect(i.beginMs, 1000);
    expect(i.endMs, 2000);
    expect(i.allDay, isTrue);
    expect(i.visible, isFalse);
    expect(i.availability, ProviderInstance.availabilityBusy);
  });

  test('ProviderTasks joins categories and drops blank ones', () {
    final r = ProviderTasks.fromMap({
      'authority': 'org.tasks.opentasks',
      'tasks': [taskRow(id: 1), taskRow(id: 2, overrideOf: 'x'), 'junk'],
      'categories': [
        {'task_id': 1, 'data1': ' reading '},
        {'task_id': 1, 'data1': 'phd'},
        {'task_id': 1, 'data1': ''},
        {'task_id': null, 'data1': 'orphan'},
      ],
    });
    expect(r.authority, 'org.tasks.opentasks');
    expect(r.tasks, hasLength(2));
    expect(r.tasks[1].isOverride, isTrue);
    expect(r.tagsByTask, {
      1: ['reading', 'phd'],
    });
    expect(ProviderTasks.fromMap(const {}).tasks, isEmpty);
  });
}
