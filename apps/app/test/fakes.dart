import 'package:davx_bridge/davx_bridge.dart';
import 'package:sasa/main.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa/src/folder_access.dart';
import 'package:sasa/src/secret_store.dart';
import 'package:sasa/src/setup_controller.dart';
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

/// [FolderAccess] over in-memory folders, keyed by location ref.
class MemoryFolderAccess implements FolderAccess {
  MemoryFolderAccess({this.nextPick});

  final Map<String, MemorySyncFolder> folders = {};
  FolderLocation? nextPick;
  bool accessible = true;
  final List<FolderLocation> forgotten = [];
  int picks = 0;

  MemorySyncFolder folder(String ref) =>
      folders.putIfAbsent(ref, MemorySyncFolder.new);

  @override
  Future<FolderLocation?> pick({FolderLocation? current}) async {
    picks++;
    return nextPick;
  }

  @override
  Future<bool> isAccessible(FolderLocation location) async => accessible;

  @override
  SyncFolder open(FolderLocation location) => folder(location.ref);

  @override
  Future<void> forget(FolderLocation location) async => forgotten.add(location);
}

const syncA = FolderLocation(
  kind: FolderKind.safTree,
  ref: 'content://tree/primary%3ASync',
  name: 'Sync',
);
const syncB = FolderLocation(
  kind: FolderKind.safTree,
  ref: 'content://tree/primary%3AOther',
  name: 'Other',
);

final testAccount = CalDavAccount(
  url: Uri.parse('https://dav.example.org/'),
  username: 'me',
  password: 'pw',
);

/// App services wired with fakes.
AppServices testServices({
  SourcePlatform platform = SourcePlatform.android,
  DeviceSettings? settings,
  SecretStore? secrets,
  MemoryFolderAccess? access,
  FakeBridge? bridge,
  CalendarSource? calDav,
  CalDavTester? tester,
  Clock? clock,
}) {
  final store = secrets ?? MemorySecretStore();
  return AppServices(
    platform: platform,
    settings: settings ?? MemoryDeviceSettings(),
    secrets: store,
    access: access ?? MemoryFolderAccess(),
    clock: clock ?? FakeClock(DateTime.utc(2026, 11, 8, 9)),
    bridge: bridge ?? FakeBridge(),
    calDav: () async =>
        calDav ?? (await store.calDavAccount() == null ? null : FakeSource()),
    testCalDav: tester,
    zone: locationFor('Europe/Paris'),
  );
}
