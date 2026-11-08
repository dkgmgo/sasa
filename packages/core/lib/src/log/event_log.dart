import 'dart:math';

import '../clock.dart';
import 'app_state.dart';
import 'events.dart';
import 'log_event.dart';
import 'sync_folder.dart';

/// A line of a log file that could not be used.
final class LogIssue {
  const LogIssue(this.path, this.line, this.reason);

  final String path;

  /// 1-based line number.
  final int line;
  final String reason;

  @override
  String toString() => '$path:$line: $reason';
}

/// Result of [EventLog.load].
final class LogSnapshot {
  LogSnapshot({
    required List<LogEvent> events,
    required this.state,
    required List<LogIssue> issues,
    required this.newerVersionEvents,
    required List<String> devices,
  }) : events = List.unmodifiable(events),
       issues = List.unmodifiable(issues),
       devices = List.unmodifiable(devices);

  /// Every distinct readable event, in fold order.
  final List<LogEvent> events;
  final AppState state;

  /// Unreadable lines and events with bad data. A torn last line after a
  /// crash shows up here; it is harmless.
  final List<LogIssue> issues;

  /// Events written by a newer app version, not applied. Non-zero means this
  /// device should update the app.
  final int newerVersionEvents;

  /// Device folders found, sorted.
  final List<String> devices;
}

/// Matches `log-YYYY-MM.jsonl` and sync tools' conflict copies of it, e.g.
/// `log-2026-11.sync-conflict-20261108-101500-ABCDEFG.jsonl`. Reading a copy
/// is safe: events are de-duplicated by id.
final _logFile = RegExp(r'^log-\d{4}-\d{2}(\..+)?\.jsonl$');

/// The append-only event log in the synced folder.
///
/// ```
/// <root>/devices/<deviceId>/log-YYYY-MM.jsonl
/// ```
///
/// This device only ever appends to its own folder, so the sync tool never
/// sees two writers on one file. [load] reads every device's files, merges
/// them by timestamp and folds them into an [AppState].
final class EventLog {
  EventLog({
    required this.folder,
    required this.deviceId,
    required this.clock,
    Random? random,
    this.root = 'Sasa',
  }) : _random = random ?? Random.secure() {
    if (!isValidDeviceId(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'not a safe folder name');
    }
    checkPath(root);
  }

  final SyncFolder folder;
  final String deviceId;
  final Clock clock;

  /// App folder inside the synced folder.
  final String root;
  final Random _random;

  String get devicesDir => '$root/devices';
  String get deviceDir => '$devicesDir/$deviceId';

  /// Serialises this instance's writes, so its own appends never interleave.
  Future<void> _tail = Future.value();

  /// Files whose end this instance has checked (or written) since opening.
  final _clean = <String>{};

  /// Appends [payload] as a new event stamped with [clock], and returns it.
  Future<LogEvent> append(EventPayload payload) {
    if (payload is UnknownEvent) {
      throw ArgumentError('Cannot write an UnknownEvent');
    }
    final event = LogEvent(
      id: uuidV4(_random),
      ts: clock.now(),
      device: deviceId,
      type: payload.type,
      v: eventSchemaVersion,
      data: payload.toJson(),
    );
    final done = _tail.then((_) => _write(event));
    _tail = done.then((_) {}, onError: (_) {});
    return done.then((_) => event);
  }

  Future<void> _write(LogEvent event) async {
    final path = '$deviceDir/${logFileName(event.ts)}';
    var prefix = '';
    if (!_clean.contains(path)) {
      // A crash may have left half a line at the end. Start on a fresh line
      // so only that torn line is lost, never this event.
      final existing = await folder.read(path);
      if (existing != null && existing.isNotEmpty && !existing.endsWith('\n')) {
        prefix = '\n';
      }
    }
    await folder.append(path, '$prefix${event.toLine()}\n');
    _clean.add(path);
  }

  /// Reads every device's logs and folds them.
  ///
  /// Never throws for bad content: unreadable lines are reported in
  /// [LogSnapshot.issues] and skipped. Folders that are not valid device ids
  /// (e.g. Syncthing's `.stfolder`) and files that are not logs (temporary
  /// files, notes) are ignored.
  Future<LogSnapshot> load() async {
    final events = <LogEvent>[];
    final issues = <LogIssue>[];
    final devices = <String>[];
    // Where each event came from, for issue reports.
    final where = <String, (String, int)>{};
    for (final dir in await folder.list(devicesDir)) {
      if (!dir.isDirectory || !isValidDeviceId(dir.name)) continue;
      devices.add(dir.name);
      final dirPath = '$devicesDir/${dir.name}';
      for (final file in await folder.list(dirPath)) {
        if (file.isDirectory || !_logFile.hasMatch(file.name)) continue;
        final path = '$dirPath/${file.name}';
        final text = await folder.read(path);
        if (text == null) continue;
        _parse(path, text, events, issues, where);
      }
    }
    var newer = 0;
    final state = AppState.fold(
      events,
      onSkipped: (e, err) {
        if (err is UnsupportedEventVersion) {
          newer++;
        } else {
          final (path, line) = where[e.id]!;
          issues.add(LogIssue(path, line, '$err'));
        }
      },
    );
    final seen = <String>{};
    final distinct = [
      for (final e in events)
        if (seen.add(e.id)) e,
    ]..sort();
    devices.sort();
    return LogSnapshot(
      events: distinct,
      state: state,
      issues: issues,
      newerVersionEvents: newer,
      devices: devices,
    );
  }

  void _parse(
    String path,
    String text,
    List<LogEvent> out,
    List<LogIssue> issues,
    Map<String, (String, int)> where,
  ) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.trim().isEmpty) continue;
      try {
        final e = LogEvent.fromLine(line);
        out.add(e);
        where.putIfAbsent(e.id, () => (path, i + 1));
      } on FormatException catch (err) {
        issues.add(LogIssue(path, i + 1, err.message));
      }
    }
  }
}
