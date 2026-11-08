import 'package:sasa_core/sasa_core.dart';

import 'dav/caldav_client.dart';
import 'ical/ical_values.dart';
import 'ical/mapping.dart';

/// Called when one calendar object cannot be parsed; it is then skipped.
/// [uri] identifies the resource; the error never contains credentials.
typedef ParseErrorHandler = void Function(Uri uri, Object error);

/// [CalendarSource] reading a CalDAV server (e.g. Radicale).
///
/// Collections are discovered on first use and cached; call
/// [refreshCollections] to re-discover. Recurrences are expanded on the
/// client; the server only narrows resources by time range.
final class CalDavSource implements CalendarSource {
  CalDavSource({
    required this.client,
    required this.zones,
    this.onParseError,
    this._collections,
  });

  final CalDavClient client;

  /// Default zone for floating times, unknown TZIDs and all-day dates: the
  /// user's configured zone.
  final ZoneResolver zones;
  final ParseErrorHandler? onParseError;

  /// Pre-selected collections; null until discovered.
  List<CalDavCollection>? _collections;

  /// The calendar collections in use (discovered once).
  Future<List<CalDavCollection>> collections() async =>
      _collections ??= await client.discoverCollections();

  /// Forgets cached collections and discovers them again.
  Future<List<CalDavCollection>> refreshCollections() async {
    _collections = null;
    return collections();
  }

  /// Server time ranges are widened by this much on each side, so all-day
  /// and floating events (which the server reads in its own zone) are never
  /// missed. Results are then filtered exactly.
  static const rangeMargin = Duration(days: 1);

  @override
  Future<List<CalEvent>> events(DateTime from, DateTime to) async {
    final out = <CalEvent>[];
    for (final c in (await collections()).where((c) => c.hasEvents)) {
      final objects = await client.queryEvents(
        c.uri,
        from.subtract(rangeMargin),
        to.add(rangeMargin),
      );
      for (final o in objects) {
        try {
          out.addAll(
            eventsFromIcal(
              o.data,
              calendarName: c.displayName,
              from: from,
              to: to,
              zones: zones,
            ),
          );
        } on FormatException catch (e) {
          onParseError?.call(o.uri, e);
        }
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return List.unmodifiable(out);
  }

  /// All tasks, completed ones included (the [CalendarSource] contract).
  /// Prefer [openTasks] when only open tasks are needed: completed tasks
  /// pile up over the years.
  @override
  Future<List<TaskItem>> tasks() => _tasks(client.queryTodos);

  /// Open tasks only: filtered on the server (no `COMPLETED` date) and on
  /// the client (`STATUS` not `COMPLETED`/`CANCELLED`).
  Future<List<TaskItem>> openTasks() async => List.unmodifiable(
    (await _tasks(client.queryOpenTodos)).where((t) => !t.completed),
  );

  Future<List<TaskItem>> _tasks(
    Future<List<CalendarObject>> Function(Uri) query,
  ) async {
    final out = <TaskItem>[];
    for (final c in (await collections()).where((c) => c.hasTasks)) {
      for (final o in await query(c.uri)) {
        try {
          out.addAll(
            tasksFromIcal(o.data, listName: c.displayName, zones: zones),
          );
        } on FormatException catch (e) {
          onParseError?.call(o.uri, e);
        }
      }
    }
    return List.unmodifiable(out);
  }
}
