import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data_controller.dart';
import '../source_controller.dart';
import 'brief_notifier.dart';

/// What the last scheduling did.
final class BriefStatus {
  const BriefStatus({this.next, this.exact = false, this.brief, this.kept});

  /// When the next brief fires; null when the brief is off.
  final DateTime? next;

  /// False when the system only allows inexact alarms: the brief may then
  /// come some minutes late.
  final bool exact;

  /// The scheduled text; null when off or [kept].
  final Brief? brief;

  /// Why the already scheduled brief was kept instead of re-rendered.
  final String? kept;
}

/// Renders the next brief and schedules it as a notification, replacing
/// the one scheduled before. Run hourly in the background and on every app
/// open, so the content is at most an hour old but fires on time.
final class BriefScheduler {
  BriefScheduler({required this.notifier, required this.clock});

  final BriefNotifier notifier;
  final Clock clock;

  /// Re-renders and reschedules the brief from [source] (null: no source
  /// set up yet).
  ///
  /// When the calendar cannot be loaded and a brief is already scheduled,
  /// that one is kept (it was rendered from real data less than a tick
  /// ago), unless [force] (the settings just changed: the time must move).
  Future<BriefStatus> reschedule({
    required AppConfig config,
    required CalendarSource? source,
    required tz.Location zone,
    bool force = false,
  }) async {
    final next = nextBriefAt(config.brief, after: clock.now(), zone: zone);
    if (next == null) {
      await notifier.cancel();
      return const BriefStatus();
    }
    final day = TodayWindow.of(next, zone);
    final events = await _attempt(
      () => source!.events(day.dayStart, day.dayEnd),
      source,
    );
    final tasks = await _attempt(() => source!.tasks(), source);
    final exact = await notifier.canScheduleExact();
    if (events == null && !force && await notifier.hasScheduled()) {
      return BriefStatus(
        next: next,
        exact: exact,
        kept: 'The calendar did not load; the brief scheduled before is kept.',
      );
    }
    final brief = BriefRenderer(clock: clock).render(
      config: config,
      events: events ?? const [],
      eventsLoaded: events != null,
      tasks: tasks ?? const [],
      zone: zone,
      at: next,
    );
    await notifier.schedule(
      title: brief.title,
      body: brief.body,
      at: tz.TZDateTime.from(next, zone),
      exact: exact,
    );
    return BriefStatus(next: next, exact: exact, brief: brief);
  }

  static Future<T?> _attempt<T>(
    Future<T> Function() load,
    CalendarSource? source,
  ) async {
    if (source == null) return null;
    try {
      return await load().timeout(const Duration(seconds: 30));
    } on Exception {
      return null;
    }
  }
}

/// Keeps the scheduled brief in line with the app's data: on start, on
/// every return to the foreground and whenever the brief settings change.
/// Exposes the result and the permissions for Settings.
final class BriefController extends ChangeNotifier {
  BriefController({
    required this.scheduler,
    required this.data,
    required this.sources,
    required this.zone,
  }) {
    data.addListener(_onData);
  }

  final BriefScheduler scheduler;
  final DataController data;
  final SourceController sources;

  /// The configured zone (with the app's fallback).
  final tz.Location Function() zone;

  BriefNotifier get notifier => scheduler.notifier;

  BriefStatus? _status;
  bool _notificationsAllowed = true;
  bool _exactAllowed = true;
  (BriefSettings, String)? _scheduledFor;
  Future<void>? _running;
  bool _again = false;
  bool _againForce = false;

  BriefStatus? get status => _status;
  bool get notificationsAllowed => _notificationsAllowed;
  bool get exactAllowed => _exactAllowed;

  /// Reschedules now; calls made while one runs are merged into one more
  /// run after it.
  Future<void> refresh({bool force = false}) {
    if (_running != null) {
      _again = true;
      _againForce |= force;
      return _running!;
    }
    return _running = _run(force).whenComplete(() {
      _running = null;
      if (_again) {
        final f = _againForce;
        _again = _againForce = false;
        unawaited(refresh(force: f));
      }
    });
  }

  Future<void> _run(bool force) async {
    final config = data.config;
    if (config == null) return;
    try {
      _status = await scheduler.reschedule(
        config: config,
        source: sources.setup?.source,
        zone: zone(),
        force: force,
      );
      _scheduledFor = (config.brief, config.timeZone);
      _notificationsAllowed = await notifier.enabled();
      _exactAllowed = await notifier.canScheduleExact();
    } on Exception catch (e) {
      _status = BriefStatus(kept: 'The brief could not be scheduled: $e');
    }
    notifyListeners();
  }

  void _onData() {
    final c = data.config;
    if (c == null || _scheduledFor == null) return;
    if (_scheduledFor != (c.brief, c.timeZone)) refresh(force: true);
  }

  /// Asks for the notification permission, then reschedules.
  Future<void> requestNotifications() async {
    await notifier.requestPermission();
    await refresh(force: true);
  }

  /// Opens the system's exact-alarm screen, then reschedules.
  Future<void> requestExact() async {
    await notifier.requestExact();
    await refresh(force: true);
  }

  @override
  void dispose() {
    data.removeListener(_onData);
    super.dispose();
  }
}
