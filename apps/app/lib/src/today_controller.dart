import 'package:flutter/foundation.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'data_controller.dart';
import 'source_controller.dart';
import 'source_setup.dart';

/// Loads today's events and the tasks from the current source and keeps the
/// Today view and the Unclassified inbox (both built in core) up to date.
///
/// Items are fetched again when the source changes, the day changes or on
/// [refresh]; a config change only rebuilds the views.
final class TodayController extends ChangeNotifier {
  TodayController({
    required this.data,
    required this.sources,
    required this.clock,
    required this.fallbackZone,
  }) {
    data.addListener(_rebuild);
    sources.addListener(_onSourceChanged);
  }

  final DataController data;
  final SourceController sources;
  final Clock clock;

  /// Used when the configured time zone is unknown.
  final tz.Location fallbackZone;

  CalendarSource? _loadedFrom;
  DateTime? _loadedDay;
  List<CalEvent> _events = const [];
  List<TaskItem> _tasks = const [];
  TodayView? _today;
  Inbox? _inbox;
  String? _eventsError;
  String? _tasksError;
  bool _loading = false;
  int _generation = 0;

  /// Null until the config and a first load are there.
  TodayView? get today => _today;
  Inbox? get inbox => _inbox;

  /// Events loaded for today and the inbox range.
  List<CalEvent> get events => _events;
  List<TaskItem> get tasks => _tasks;
  String? get eventsError => _eventsError;
  String? get tasksError => _tasksError;
  bool get loading => _loading;
  bool get loaded => _loadedFrom != null;

  /// Zone of the configured `timeZone`.
  tz.Location get zone {
    final name = data.config?.timeZone;
    if (name == null) return fallbackZone;
    try {
      return locationFor(name);
    } on Exception {
      return fallbackZone;
    }
  }

  /// Fetches events and tasks again.
  Future<void> refresh() async {
    final source = sources.setup?.source;
    if (source == null) return;
    final gen = ++_generation;
    final window = TodayWindow.of(clock.now(), zone);
    _loading = true;
    notifyListeners();
    final (events, eventsError) = await _fetch(
      () => source.events(window.dayStart, window.fetchEnd),
    );
    final (tasks, tasksError) = await _fetch(source.tasks);
    if (gen != _generation) return;
    _loadedFrom = source;
    _loadedDay = window.dayStart;
    _events = events ?? const [];
    _tasks = tasks ?? const [];
    _eventsError = eventsError;
    _tasksError = tasksError;
    _loading = false;
    _rebuild();
  }

  /// Call every minute or so: moves "now" and reloads when the day changed.
  Future<void> tick() async {
    final day = TodayWindow.of(clock.now(), zone).dayStart;
    if (_loadedDay != null && day != _loadedDay) return refresh();
    _rebuild();
  }

  void _onSourceChanged() {
    final source = sources.setup?.source;
    if (source != null && !identical(source, _loadedFrom) && !sources.busy) {
      refresh();
    }
  }

  void _rebuild() {
    final config = data.config;
    if (config == null || !loaded) {
      _today = null;
      _inbox = null;
    } else {
      _today = buildToday(
        config: config,
        events: _events,
        eventsLoaded: _eventsError == null,
        tasks: _tasks,
        now: clock.now(),
        zone: zone,
      );
      _inbox = buildInbox(config: config, events: _events, tasks: _tasks);
    }
    notifyListeners();
  }

  static Future<(T?, String?)> _fetch<T>(Future<T> Function() load) async {
    try {
      return (await load(), null);
    } on SourceUnavailable catch (e) {
      return (
        null,
        e.reason == calDavNotConfigured
            ? 'No CalDAV account yet: add one in Settings.'
            : 'Source unavailable: ${e.reason}.',
      );
    } on Exception catch (e) {
      return (null, 'Could not load: $e');
    }
  }

  @override
  void dispose() {
    data.removeListener(_rebuild);
    sources.removeListener(_onSourceChanged);
    super.dispose();
  }
}
