// Pure Dart: CalendarSource on top of DavxBridgeApi.

import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'mapping.dart';
import 'provider_rows.dart';

/// [CalendarSource] reading the Android providers that DAVx⁵ syncs into:
/// `CalendarContract.Instances` (recurrences already expanded) and the
/// OpenTasks-compatible task provider of Tasks.org.
///
/// By default only DAVx⁵ calendars and lists are used, so the result matches
/// the CalDAV path; [includeAllCalendars] also reads device calendars and
/// other sync adapters' lists. Calls throw [SourceUnavailable] when a
/// permission is missing or no task provider is installed.
final class DavxProviderSource implements CalendarSource {
  DavxProviderSource({
    required this.bridge,
    required this.zone,
    this.includeAllCalendars = false,
  });

  final DavxBridgeApi bridge;

  /// The user's configured zone, for all-day dates.
  final tz.Location zone;
  final bool includeAllCalendars;

  bool _wanted(String? accountType) =>
      includeAllCalendars || isDavxAccount(accountType);

  @override
  Future<List<CalEvent>> events(DateTime from, DateTime to) async {
    final rows = await bridge.instances(from, to);
    final out = <CalEvent>[
      for (final r in rows)
        if (r.visible && _wanted(r.accountType))
          if (calEventOf(r) case final e? when overlaps(e, from, to, zone)) e,
    ];
    out.sort((a, b) => a.start.compareTo(b.start));
    return List.unmodifiable(out);
  }

  /// All tasks, completed ones included. Recurrence overrides are skipped,
  /// like the CalDAV path.
  @override
  Future<List<TaskItem>> tasks() async {
    final res = await bridge.tasks();
    return List.unmodifiable([
      for (final t in res.tasks)
        if (!t.isOverride && _wanted(t.accountType))
          taskItemOf(t, res.tagsByTask[t.id] ?? const [], zone),
    ]);
  }

  /// Device state for `SourceSelector`, without prompting.
  Future<ProviderProbe> probe() async {
    final s = await bridge.status();
    if (!s.calendarPermission) {
      return const ProviderProbe(calendarPermission: false, davxCalendars: 0);
    }
    final calendars = await bridge.calendars();
    return ProviderProbe(
      calendarPermission: true,
      davxCalendars: calendars.where((c) => c.isDavx).length,
    );
  }
}
