import 'package:davx_bridge/davx_bridge.dart';
import 'package:sasa/main.dart';
import 'package:sasa/src/brief/brief_notifier.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa/src/folder_access.dart';
import 'package:sasa/src/secret_store.dart';
import 'package:sasa/src/setup_controller.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

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
  BriefNotifier? briefNotifier,
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
    briefNotifier: briefNotifier,
  );
}

/// Records what would be scheduled instead of talking to Android.
final class FakeBriefNotifier implements BriefNotifier {
  FakeBriefNotifier({this.exact = true, this.allowed = true});

  bool exact;
  bool allowed;
  bool grantOnRequest = true;
  int permissionRequests = 0;
  int exactRequests = 0;
  int cancels = 0;
  void Function()? onOpenToday;

  /// Every schedule call, newest last.
  final scheduled =
      <({String title, String body, tz.TZDateTime at, bool exact})>[];

  /// The pending brief; cleared by [cancel].
  ({String title, String body, tz.TZDateTime at, bool exact})? pending;

  @override
  Future<void> init({void Function()? onOpenToday}) async =>
      this.onOpenToday = onOpenToday;

  @override
  Future<void> schedule({
    required String title,
    required String body,
    required tz.TZDateTime at,
    required bool exact,
  }) async {
    final s = (title: title, body: body, at: at, exact: exact);
    scheduled.add(s);
    pending = s;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    pending = null;
  }

  @override
  Future<bool> hasScheduled() async => pending != null;

  @override
  Future<bool> canScheduleExact() async => exact;

  @override
  Future<void> requestExact() async {
    exactRequests++;
    exact = true;
  }

  @override
  Future<bool> enabled() async => allowed;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    if (grantOnRequest) allowed = true;
    return allowed;
  }
}
