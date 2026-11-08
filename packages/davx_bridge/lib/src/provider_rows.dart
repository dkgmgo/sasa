// Pure Dart: raw rows as the Kotlin side sends them, and the bridge API.

/// Account types used by DAVx⁵ (`bitfire.at.davdroid`) and managed DAVx⁵
/// (`com.davdroid`) for calendars and task lists.
const davxAccountTypes = {'bitfire.at.davdroid', 'com.davdroid'};

/// Whether [accountType] belongs to DAVx⁵.
bool isDavxAccount(String? accountType) =>
    accountType != null && davxAccountTypes.contains(accountType);

/// Permission and provider state reported by the device. Never prompts.
final class BridgeStatus {
  const BridgeStatus({
    required this.calendarPermission,
    required this.taskAuthority,
    required this.taskPermission,
    this.prompted = false,
  });

  factory BridgeStatus.fromMap(Map<Object?, Object?> m) => BridgeStatus(
    calendarPermission: m['calendarPermission'] == true,
    taskAuthority: _str(m, 'taskAuthority'),
    taskPermission: m['taskPermission'] == true,
    prompted: m['prompted'] == true,
  );

  /// `READ_CALENDAR` granted.
  final bool calendarPermission;

  /// Authority of the installed task provider (`org.tasks.opentasks` or
  /// `org.dmfs.tasks`), null when none is installed.
  final String? taskAuthority;

  /// Read permission of [taskAuthority] granted.
  final bool taskPermission;

  /// A permission dialog was shown (false in background engines).
  final bool prompted;

  @override
  String toString() =>
      'BridgeStatus(calendar: $calendarPermission, tasks: '
      '${taskAuthority ?? 'none'}/$taskPermission)';
}

/// A row of `CalendarContract.Calendars`.
final class ProviderCalendar {
  const ProviderCalendar({
    required this.id,
    required this.displayName,
    required this.accountName,
    required this.accountType,
    required this.visible,
    required this.syncEvents,
  });

  factory ProviderCalendar.fromMap(Map<Object?, Object?> m) => ProviderCalendar(
    id: _int(m, '_id') ?? 0,
    displayName: _str(m, 'calendar_displayName') ?? '',
    accountName: _str(m, 'account_name'),
    accountType: _str(m, 'account_type'),
    visible: _flag(m, 'visible', ifNull: true),
    syncEvents: _flag(m, 'sync_events', ifNull: true),
  );

  final int id;
  final String displayName;
  final String? accountName;
  final String? accountType;
  final bool visible;
  final bool syncEvents;

  bool get isDavx => isDavxAccount(accountType);
}

/// A row of `CalendarContract.Instances` (one occurrence of an event).
final class ProviderInstance {
  const ProviderInstance({
    required this.eventId,
    required this.beginMs,
    required this.endMs,
    required this.title,
    required this.allDay,
    required this.availability,
    required this.location,
    required this.description,
    required this.uid,
    required this.status,
    required this.calendarName,
    required this.accountType,
    required this.visible,
  });

  factory ProviderInstance.fromMap(Map<Object?, Object?> m) {
    final begin = _int(m, 'begin');
    if (begin == null) throw const FormatException('Instance without begin');
    return ProviderInstance(
      eventId: _int(m, 'event_id') ?? 0,
      beginMs: begin,
      endMs: _int(m, 'end') ?? begin,
      title: _str(m, 'title'),
      allDay: _flag(m, 'allDay'),
      availability: _int(m, 'availability') ?? availabilityBusy,
      location: _str(m, 'eventLocation'),
      description: _str(m, 'description'),
      uid: _str(m, 'uid2445'),
      status: _int(m, 'eventStatus'),
      calendarName: _str(m, 'calendar_displayName') ?? '',
      accountType: _str(m, 'account_type'),
      visible: _flag(m, 'visible', ifNull: true),
    );
  }

  // CalendarContract.Events.AVAILABILITY_* and STATUS_CANCELED.
  static const availabilityBusy = 0;
  static const availabilityFree = 1;
  static const availabilityTentative = 2;
  static const statusCancelled = 2;

  final int eventId;
  final int beginMs;
  final int endMs;
  final String? title;
  final bool allDay;
  final int availability;
  final String? location;
  final String? description;

  /// iCalendar `UID` (`UID_2445`); null for events created on the device
  /// before their first sync.
  final String? uid;
  final int? status;
  final String calendarName;
  final String? accountType;
  final bool visible;
}

/// A row of the OpenTasks `tasks` view (task joined with its list).
final class ProviderTask {
  const ProviderTask({
    required this.id,
    required this.uid,
    required this.title,
    required this.listName,
    required this.accountType,
    required this.dueMs,
    required this.dueAllDay,
    required this.priority,
    required this.status,
    required this.completedMs,
    required this.isOverride,
  });

  factory ProviderTask.fromMap(Map<Object?, Object?> m) => ProviderTask(
    id: _int(m, '_id') ?? 0,
    uid: _str(m, '_uid'),
    title: _str(m, 'title'),
    listName: _str(m, 'list_name') ?? '',
    accountType: _str(m, 'account_type'),
    dueMs: _int(m, 'due'),
    dueAllDay: _flag(m, 'is_allday'),
    priority: _int(m, 'priority'),
    status: _int(m, 'status'),
    completedMs: _int(m, 'completed'),
    isOverride:
        _str(m, 'original_instance_sync_id') != null ||
        _int(m, 'original_instance_id') != null,
  );

  // TaskContract.Tasks.STATUS_*.
  static const statusNeedsAction = 0;
  static const statusInProcess = 1;
  static const statusCompleted = 2;
  static const statusCancelled = 3;

  final int id;
  final String? uid;
  final String? title;
  final String listName;
  final String? accountType;

  /// Epoch ms; for a date-only due ([dueAllDay]) it is UTC midnight.
  final int? dueMs;
  final bool dueAllDay;

  /// iCalendar priority, 0 = undefined.
  final int? priority;
  final int? status;
  final int? completedMs;

  /// A `RECURRENCE-ID` override of a recurring task.
  final bool isOverride;
}

/// Everything `tasks()` returns: the task rows and their categories (tags).
final class ProviderTasks {
  const ProviderTasks({
    required this.authority,
    required this.tasks,
    required this.tagsByTask,
  });

  factory ProviderTasks.fromMap(Map<Object?, Object?> m) {
    final tags = <int, List<String>>{};
    for (final c in _rows(m['categories'])) {
      final id = _int(c, 'task_id');
      final name = _str(c, 'data1')?.trim();
      if (id == null || name == null || name.isEmpty) continue;
      (tags[id] ??= []).add(name);
    }
    return ProviderTasks(
      authority: _str(m, 'authority') ?? '',
      tasks: [for (final r in _rows(m['tasks'])) ProviderTask.fromMap(r)],
      tagsByTask: tags,
    );
  }

  final String authority;
  final List<ProviderTask> tasks;
  final Map<int, List<String>> tagsByTask;
}

/// The device side of the bridge. The channel implementation throws core's
/// `SourceUnavailable` for a missing permission or provider; a fake
/// implements it in tests.
abstract interface class DavxBridgeApi {
  /// Current permissions and provider; never prompts.
  Future<BridgeStatus> status();

  /// Shows the system prompt for the missing permissions when the app is in
  /// the foreground; in a background engine it only reports [status].
  Future<BridgeStatus> requestPermissions({
    bool calendar = true,
    bool tasks = true,
  });

  Future<List<ProviderCalendar>> calendars();

  /// Instances overlapping `[start, end)`, widened by a day on each side by
  /// the device; callers filter exactly.
  Future<List<ProviderInstance>> instances(DateTime start, DateTime end);

  Future<ProviderTasks> tasks();
}

/// Rows of a list of maps; anything else yields no rows.
Iterable<Map<Object?, Object?>> rowsOf(Object? value) => _rows(value);

Iterable<Map<Object?, Object?>> _rows(Object? value) sync* {
  if (value is! List<Object?>) return;
  for (final r in value) {
    if (r is Map<Object?, Object?>) yield r;
  }
}

int? _int(Map<Object?, Object?> m, String k) => switch (m[k]) {
  final int v => v,
  final double v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};

String? _str(Map<Object?, Object?> m, String k) => switch (m[k]) {
  final String v when v.trim().isNotEmpty => v,
  _ => null,
};

bool _flag(Map<Object?, Object?> m, String k, {bool ifNull = false}) =>
    switch (m[k]) {
      null => ifNull,
      final bool v => v,
      final int v => v != 0,
      final String v => v == '1' || v.toLowerCase() == 'true',
      _ => ifNull,
    };
