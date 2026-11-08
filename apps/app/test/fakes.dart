import 'package:davx_bridge/davx_bridge.dart';
import 'package:sasa_core/sasa_core.dart';

/// Scriptable [DavxBridgeApi] for app tests.
final class FakeBridge implements DavxBridgeApi {
  FakeBridge({
    this.calendarPermission = true,
    this.taskAuthority = 'org.tasks.opentasks',
    this.taskPermission = true,
    this.davxCalendars = 1,
    this.grantOnRequest = false,
  });

  bool calendarPermission;
  String? taskAuthority;
  bool taskPermission;
  int davxCalendars;
  bool grantOnRequest;
  int requests = 0;
  int statusCalls = 0;

  BridgeStatus get _status => BridgeStatus(
    calendarPermission: calendarPermission,
    taskAuthority: taskAuthority,
    taskPermission: taskPermission,
  );

  @override
  Future<BridgeStatus> status() async {
    statusCalls++;
    return _status;
  }

  @override
  Future<BridgeStatus> requestPermissions({
    bool calendar = true,
    bool tasks = true,
  }) async {
    requests++;
    if (grantOnRequest) {
      calendarPermission = true;
      taskPermission = taskAuthority != null;
    }
    return _status;
  }

  @override
  Future<List<ProviderCalendar>> calendars() async {
    if (!calendarPermission) throw const SourceUnavailable('denied');
    return [
      for (var i = 0; i < davxCalendars; i++)
        ProviderCalendar.fromMap({
          '_id': i,
          'calendar_displayName': 'Cal $i',
          'account_type': 'bitfire.at.davdroid',
        }),
    ];
  }

  @override
  Future<List<ProviderInstance>> instances(DateTime start, DateTime end) async {
    if (!calendarPermission) throw const SourceUnavailable('denied');
    return [
      ProviderInstance.fromMap({
        'event_id': 1,
        'begin': start.add(const Duration(hours: 9)).millisecondsSinceEpoch,
        'end': start.add(const Duration(hours: 10)).millisecondsSinceEpoch,
        'title': 'Phone event',
        'uid2445': 'phone',
        'calendar_displayName': 'PhD',
        'account_type': 'bitfire.at.davdroid',
      }),
    ];
  }

  @override
  Future<ProviderTasks> tasks() async {
    if (taskAuthority == null) throw const SourceUnavailable('no provider');
    if (!taskPermission) throw const SourceUnavailable('denied');
    return ProviderTasks.fromMap({
      'authority': taskAuthority,
      'tasks': [
        {
          '_id': 1,
          '_uid': 'phone-task',
          'title': 'Phone task',
          'list_name': 'PhD',
          'account_type': 'bitfire.at.davdroid',
        },
      ],
    });
  }
}
