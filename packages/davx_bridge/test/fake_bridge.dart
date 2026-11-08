import 'package:davx_bridge/davx_bridge.dart';
import 'package:sasa_core/sasa_core.dart';

/// In-memory [DavxBridgeApi]; set [unavailable] to simulate a denied
/// permission or missing provider.
final class FakeBridge implements DavxBridgeApi {
  BridgeStatus statusValue = const BridgeStatus(
    calendarPermission: true,
    taskAuthority: 'org.tasks.opentasks',
    taskPermission: true,
  );
  List<Map<Object?, Object?>> calendarRows = [];
  List<Map<Object?, Object?>> instanceRows = [];
  Map<Object?, Object?> taskResult = const {};
  final Set<String> unavailable = {};
  final List<(DateTime, DateTime)> instanceCalls = [];

  void _check(String op) {
    if (unavailable.contains(op)) throw SourceUnavailable('$op denied');
  }

  @override
  Future<BridgeStatus> status() async => statusValue;

  @override
  Future<BridgeStatus> requestPermissions({
    bool calendar = true,
    bool tasks = true,
  }) async => statusValue;

  @override
  Future<List<ProviderCalendar>> calendars() async {
    _check('calendars');
    return [for (final r in calendarRows) ProviderCalendar.fromMap(r)];
  }

  @override
  Future<List<ProviderInstance>> instances(DateTime start, DateTime end) async {
    _check('instances');
    instanceCalls.add((start, end));
    return [for (final r in instanceRows) ProviderInstance.fromMap(r)];
  }

  @override
  Future<ProviderTasks> tasks() async {
    _check('tasks');
    return ProviderTasks.fromMap(taskResult);
  }
}

int ms(DateTime d) => d.millisecondsSinceEpoch;

/// An instance row as the Kotlin side sends it.
Map<Object?, Object?> instanceRow({
  int eventId = 1,
  required DateTime begin,
  required DateTime end,
  String? title = 'Event',
  int allDay = 0,
  int availability = 0,
  String? uid = 'uid-1',
  int? status = 1,
  String calendar = 'PhD',
  String accountType = 'bitfire.at.davdroid',
  int visible = 1,
  String? location,
  String? description,
}) => {
  'event_id': eventId,
  'begin': ms(begin),
  'end': ms(end),
  'title': title,
  'allDay': allDay,
  'availability': availability,
  'eventLocation': location,
  'description': description,
  'uid2445': uid,
  'eventStatus': status,
  'calendar_id': 3,
  'calendar_displayName': calendar,
  'account_type': accountType,
  'account_name': 'test@radicale',
  'visible': visible,
};

/// A task row of the OpenTasks `tasks` view.
Map<Object?, Object?> taskRow({
  int id = 1,
  String? uid = 'task-1',
  String? title = 'Task',
  String list = 'PhD',
  String accountType = 'bitfire.at.davdroid',
  int? due,
  int allDay = 0,
  int? priority,
  int? status = 0,
  int? completed,
  String? overrideOf,
}) => {
  '_id': id,
  '_uid': uid,
  'title': title,
  'list_id': 7,
  'list_name': list,
  'account_type': accountType,
  'account_name': 'test@radicale',
  'due': due,
  'is_allday': allDay,
  'tz': allDay == 1 ? null : 'Europe/Paris',
  'priority': priority,
  'status': status,
  'completed': completed,
  'original_instance_sync_id': overrideOf,
  'original_instance_id': null,
};
