import '../json.dart';
import '../models/energy.dart';
import '../models/focus_session.dart';
import 'events.dart';
import 'log_event.dart';

/// A focus session that has started and not ended yet.
final class ActiveSession {
  const ActiveSession({
    required this.sessionId,
    required this.activityId,
    required this.categoryId,
    required this.plannedMin,
    required this.start,
    required this.device,
  });

  final String sessionId;
  final String activityId;
  final String categoryId;
  final int plannedMin;
  final DateTime start;

  /// Device the session runs on.
  final String device;

  @override
  bool operator ==(Object other) =>
      other is ActiveSession &&
      other.sessionId == sessionId &&
      other.activityId == activityId &&
      other.categoryId == categoryId &&
      other.plannedMin == plannedMin &&
      other.start == start &&
      other.device == device;

  @override
  int get hashCode =>
      Object.hash(sessionId, activityId, categoryId, plannedMin, start, device);
}

/// A suggestion that was shown or skipped, at [at].
final class SuggestionRecord {
  const SuggestionRecord(this.at, this.activityId, this.categoryId);

  final DateTime at;
  final String activityId;
  final String categoryId;

  @override
  bool operator ==(Object other) =>
      other is SuggestionRecord &&
      other.at == at &&
      other.activityId == activityId &&
      other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(at, activityId, categoryId);
}

/// What happened to one nudge most recently.
final class NudgeState {
  const NudgeState({this.lastFired, this.lastDismissed, this.snoozedUntil});

  final DateTime? lastFired;
  final DateTime? lastDismissed;
  final DateTime? snoozedUntil;

  NudgeState _with({DateTime? fired, DateTime? dismissed, DateTime? snoozed}) =>
      NudgeState(
        lastFired: fired ?? lastFired,
        lastDismissed: dismissed ?? lastDismissed,
        snoozedUntil: snoozed ?? snoozedUntil,
      );

  @override
  bool operator ==(Object other) =>
      other is NudgeState &&
      other.lastFired == lastFired &&
      other.lastDismissed == lastDismissed &&
      other.snoozedUntil == snoozedUntil;

  @override
  int get hashCode => Object.hash(lastFired, lastDismissed, snoozedUntil);

  @override
  String toString() =>
      'NudgeState(fired $lastFired, dismissed $lastDismissed, '
      'snoozed $snoozedUntil)';
}

/// A paper in the reading queue.
final class PaperRecord {
  const PaperRecord({
    required this.paperId,
    required this.title,
    required this.source,
    required this.status,
    required this.addedAt,
    this.doi,
    this.arxivId,
    this.statusChangedAt,
    this.note,
  });

  final String paperId;
  final String title;
  final String source;
  final String? doi;
  final String? arxivId;
  final PaperStatus status;
  final DateTime addedAt;
  final DateTime? statusChangedAt;
  final String? note;

  PaperRecord _withStatus(PaperStatusChanged c, DateTime at) => PaperRecord(
    paperId: paperId,
    title: title,
    source: source,
    doi: doi,
    arxivId: arxivId,
    status: c.status,
    addedAt: addedAt,
    statusChangedAt: at,
    note: c.note ?? note,
  );

  @override
  bool operator ==(Object other) =>
      other is PaperRecord &&
      other.paperId == paperId &&
      other.title == title &&
      other.source == source &&
      other.doi == doi &&
      other.arxivId == arxivId &&
      other.status == status &&
      other.addedAt == addedAt &&
      other.statusChangedAt == statusChangedAt &&
      other.note == note;

  @override
  int get hashCode => Object.hash(
    paperId,
    title,
    source,
    doi,
    arxivId,
    status,
    addedAt,
    statusChangedAt,
    note,
  );
}

/// A deadline on the radar.
final class DeadlineRecord {
  const DeadlineRecord({
    required this.deadlineId,
    required this.title,
    required this.due,
    required this.hoursLeft,
    required this.categoryId,
    required this.done,
    required this.updatedAt,
  });

  final String deadlineId;
  final String title;
  final DateTime due;
  final double hoursLeft;
  final String categoryId;
  final bool done;

  /// Time of the last event that changed it.
  final DateTime updatedAt;

  DeadlineRecord _update(DeadlineUpdated u, DateTime at) => DeadlineRecord(
    deadlineId: deadlineId,
    title: u.title ?? title,
    due: u.due?.toUtc() ?? due,
    hoursLeft: u.hoursLeft ?? hoursLeft,
    categoryId: u.categoryId ?? categoryId,
    done: u.done ?? done,
    updatedAt: at,
  );

  @override
  bool operator ==(Object other) =>
      other is DeadlineRecord &&
      other.deadlineId == deadlineId &&
      other.title == title &&
      other.due == due &&
      other.hoursLeft == hoursLeft &&
      other.categoryId == categoryId &&
      other.done == done &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    deadlineId,
    title,
    due,
    hoursLeft,
    categoryId,
    done,
    updatedAt,
  );
}

/// An energy check-in.
final class EnergyRecord {
  const EnergyRecord(this.at, this.energy);

  final DateTime at;
  final Energy energy;

  @override
  bool operator ==(Object other) =>
      other is EnergyRecord && other.at == at && other.energy == energy;

  @override
  int get hashCode => Object.hash(at, energy);

  @override
  String toString() => 'EnergyRecord($at, ${energy.name})';
}

/// Called for an event the fold could not apply: a newer schema version or
/// bad data for a known type.
typedef SkippedEventHandler = void Function(LogEvent event, Object error);

/// Everything the app knows from the merged device logs.
///
/// Built by [AppState.fold]; immutable.
final class AppState {
  AppState._({
    required List<FocusSession> sessions,
    required Map<String, ActiveSession> activeSessions,
    required List<SuggestionRecord> shown,
    required List<SuggestionRecord> skips,
    required Map<String, NudgeState> nudges,
    required Map<String, DateTime> teachingPrepared,
    required Map<String, PaperRecord> papers,
    required Map<String, DeadlineRecord> deadlines,
    required List<EnergyRecord> energy,
    required this.eventCount,
    required this.lastEventAt,
  }) : sessions = List.unmodifiable(sessions),
       activeSessions = Map.unmodifiable(activeSessions),
       shown = List.unmodifiable(shown),
       skips = List.unmodifiable(skips),
       nudges = Map.unmodifiable(nudges),
       _teachingPrepared = Map.unmodifiable(teachingPrepared),
       papers = Map.unmodifiable(papers),
       deadlines = Map.unmodifiable(deadlines),
       energy = List.unmodifiable(energy);

  /// State of an empty log.
  static final AppState empty = AppState.fold(const []);

  /// Folds [events] into a state.
  ///
  /// Events are de-duplicated by id and applied in [LogEvent] order (ts, then
  /// device, then id), so the result never depends on the order of [events]
  /// or on which device folds them. Unknown types are ignored; newer versions
  /// and bad data are reported to [onSkipped] and ignored.
  factory AppState.fold(
    Iterable<LogEvent> events, {
    SkippedEventHandler? onSkipped,
  }) {
    final byId = <String, LogEvent>{};
    for (final e in events) {
      // Same id ⇒ same event (a duplicate from a sync conflict copy).
      byId.putIfAbsent(e.id, () => e);
    }
    final ordered = byId.values.toList()..sort();
    final f = _Folder();
    for (final e in ordered) {
      final EventPayload p;
      try {
        p = decodePayload(e);
      } on Object catch (err) {
        if (err is! FormatException && err is! UnsupportedEventVersion) {
          rethrow;
        }
        onSkipped?.call(e, err);
        continue;
      }
      f.apply(e, p);
    }
    return f.build(ordered.length, ordered.isEmpty ? null : ordered.last.ts);
  }

  /// Ended sessions (completed and abandoned), by start time.
  final List<FocusSession> sessions;

  /// Sessions started and not yet ended, by session id.
  final Map<String, ActiveSession> activeSessions;

  /// Every shown suggestion, oldest first.
  final List<SuggestionRecord> shown;

  /// Every skipped suggestion, oldest first.
  final List<SuggestionRecord> skips;

  /// Per nudge id.
  final Map<String, NudgeState> nudges;

  /// Prepared teaching occurrences, keyed by [_teachingKey].
  final Map<String, DateTime> _teachingPrepared;

  /// Reading queue, by paper id.
  final Map<String, PaperRecord> papers;

  /// Deadlines, by id.
  final Map<String, DeadlineRecord> deadlines;

  /// Energy check-ins, oldest first.
  final List<EnergyRecord> energy;

  /// Number of distinct events seen (applied or not).
  final int eventCount;

  /// Timestamp of the newest event.
  final DateTime? lastEventAt;

  EnergyRecord? get latestEnergy => energy.isEmpty ? null : energy.last;

  /// Number of skips of [activityId] at or after [since].
  int skipsOf(String activityId, {required DateTime since}) => skips
      .where((s) => s.activityId == activityId && !s.at.isBefore(since))
      .length;

  /// Whether the occurrence of [eventUid] starting at [eventStart] was
  /// marked as prepared.
  bool isTeachingPrepared(String eventUid, DateTime eventStart) =>
      _teachingPrepared.containsKey(_teachingKey(eventUid, eventStart));

  @override
  bool operator ==(Object other) =>
      other is AppState &&
      other.eventCount == eventCount &&
      other.lastEventAt == lastEventAt &&
      listEquals(other.sessions, sessions) &&
      _mapEquals(other.activeSessions, activeSessions) &&
      listEquals(other.shown, shown) &&
      listEquals(other.skips, skips) &&
      _mapEquals(other.nudges, nudges) &&
      _mapEquals(other._teachingPrepared, _teachingPrepared) &&
      _mapEquals(other.papers, papers) &&
      _mapEquals(other.deadlines, deadlines) &&
      listEquals(other.energy, energy);

  @override
  int get hashCode => Object.hash(
    eventCount,
    lastEventAt,
    sessions.length,
    skips.length,
    papers.length,
  );

  @override
  String toString() =>
      'AppState($eventCount events, ${sessions.length} sessions, '
      '${activeSessions.length} active, ${skips.length} skips)';
}

String _teachingKey(String uid, DateTime start) =>
    '$uid@${start.toUtc().toIso8601String()}';

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}

/// Mutable accumulator behind [AppState.fold].
final class _Folder {
  final sessions = <String, FocusSession>{};
  final active = <String, ActiveSession>{};
  final shown = <SuggestionRecord>[];
  final skips = <SuggestionRecord>[];
  final nudges = <String, NudgeState>{};
  final teaching = <String, DateTime>{};
  final papers = <String, PaperRecord>{};
  final deadlines = <String, DeadlineRecord>{};
  final energy = <EnergyRecord>[];

  // Changes that arrived (in ts order) before the record they change, e.g.
  // from a device whose clock is behind. Applied, in order, when the record
  // appears, as if they happened then.
  final pendingPaper = <String, List<PaperStatusChanged>>{};
  final pendingDeadline = <String, List<DeadlineUpdated>>{};

  void apply(LogEvent e, EventPayload p) {
    final at = e.ts;
    switch (p) {
      case SessionStarted():
        // An end already seen (skewed clocks) wins over a late start.
        if (sessions.containsKey(p.sessionId)) return;
        active.putIfAbsent(
          p.sessionId,
          () => ActiveSession(
            sessionId: p.sessionId,
            activityId: p.activityId,
            categoryId: p.categoryId,
            plannedMin: p.plannedMin,
            start: p.start,
            device: e.device,
          ),
        );
      case SessionEnded():
        active.remove(p.sessionId);
        sessions.putIfAbsent(
          p.sessionId,
          () => FocusSession(
            id: p.sessionId,
            activityId: p.activityId,
            categoryId: p.categoryId,
            start: p.start,
            end: p.end,
            completed: p is SessionCompleted,
            note: p.note,
          ),
        );
      case SuggestionShown():
        shown.add(SuggestionRecord(at, p.activityId, p.categoryId));
      case SuggestionSkipped():
        skips.add(SuggestionRecord(at, p.activityId, p.categoryId));
      case NudgeFired():
        nudges[p.nudgeId] = _nudge(p.nudgeId)._with(fired: at);
      case NudgeDismissed():
        nudges[p.nudgeId] = _nudge(p.nudgeId)._with(dismissed: at);
      case NudgeSnoozed():
        nudges[p.nudgeId] = _nudge(p.nudgeId)._with(snoozed: p.until);
      case TeachingPrepared():
        teaching.putIfAbsent(_teachingKey(p.eventUid, p.eventStart), () => at);
      case PaperAdded():
        if (papers.containsKey(p.paperId)) return;
        var record = PaperRecord(
          paperId: p.paperId,
          title: p.title,
          source: p.source,
          doi: p.doi,
          arxivId: p.arxivId,
          status: PaperStatus.toRead,
          addedAt: at,
        );
        for (final c
            in pendingPaper.remove(p.paperId) ?? const <PaperStatusChanged>[]) {
          record = record._withStatus(c, at);
        }
        papers[p.paperId] = record;
      case PaperStatusChanged():
        final record = papers[p.paperId];
        if (record == null) {
          (pendingPaper[p.paperId] ??= []).add(p);
        } else {
          papers[p.paperId] = record._withStatus(p, at);
        }
      case DeadlineAdded():
        if (deadlines.containsKey(p.deadlineId)) return;
        var record = DeadlineRecord(
          deadlineId: p.deadlineId,
          title: p.title,
          due: p.due,
          hoursLeft: p.hoursLeft,
          categoryId: p.categoryId,
          done: false,
          updatedAt: at,
        );
        for (final u
            in pendingDeadline.remove(p.deadlineId) ??
                const <DeadlineUpdated>[]) {
          record = record._update(u, at);
        }
        deadlines[p.deadlineId] = record;
      case DeadlineUpdated():
        final record = deadlines[p.deadlineId];
        if (record == null) {
          (pendingDeadline[p.deadlineId] ??= []).add(p);
        } else {
          deadlines[p.deadlineId] = record._update(p, at);
        }
      case EnergyCheckin():
        energy.add(EnergyRecord(at, p.energy));
      case UnknownEvent():
        break;
    }
  }

  NudgeState _nudge(String id) => nudges[id] ?? const NudgeState();

  AppState build(int count, DateTime? last) => AppState._(
    sessions: sessions.values.toList()
      ..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      }),
    activeSessions: active,
    shown: shown,
    skips: skips,
    nudges: nudges,
    teachingPrepared: teaching,
    papers: papers,
    deadlines: deadlines,
    energy: energy,
    eventCount: count,
    lastEventAt: last,
  );
}
