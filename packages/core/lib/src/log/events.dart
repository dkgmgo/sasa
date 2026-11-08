/// Typed event data written to the device logs.
///
/// Each payload knows its `type` string and JSON shape. [decodePayload] turns
/// a [LogEvent] back into one, migrating older schema versions first.
library;

import '../json.dart';
import '../models/energy.dart';
import '../time_zones.dart';
import 'log_event.dart';

/// Schema version of event data written by this code.
///
/// Bump it when a payload's JSON changes incompatibly, and add an upcaster to
/// [_upcasters] that rewrites the previous version's data.
const int eventSchemaVersion = 1;

/// `_upcasters[n]` turns version-n event data into version n+1.
final Map<int, Map<String, Object?> Function(String type, Json data)>
_upcasters = {};

/// Thrown by [decodePayload] for an event written by a newer app version.
final class UnsupportedEventVersion implements Exception {
  const UnsupportedEventVersion(this.found);
  final int found;

  @override
  String toString() =>
      'UnsupportedEventVersion: event schema $found, this app reads up to '
      '$eventSchemaVersion';
}

/// True when this app can read [e]'s data.
bool isSupportedVersion(LogEvent e) => e.v <= eventSchemaVersion;

/// Every event type this app writes and folds.
const Set<String> knownEventTypes = {
  SessionStarted.typeName,
  SessionCompleted.typeName,
  SessionAbandoned.typeName,
  SuggestionShown.typeName,
  SuggestionSkipped.typeName,
  NudgeFired.typeName,
  NudgeDismissed.typeName,
  NudgeSnoozed.typeName,
  TeachingPrepared.typeName,
  PaperAdded.typeName,
  PaperStatusChanged.typeName,
  DeadlineAdded.typeName,
  DeadlineUpdated.typeName,
  EnergyCheckin.typeName,
};

/// Decodes [e]'s data. Unknown types give [UnknownEvent]; a newer schema
/// version throws [UnsupportedEventVersion]; bad data for a known type throws
/// [FormatException].
EventPayload decodePayload(LogEvent e) {
  if (!isSupportedVersion(e)) throw UnsupportedEventVersion(e.v);
  var data = e.data;
  for (var v = e.v; v < eventSchemaVersion; v++) {
    data = _upcasters[v]!(e.type, data);
  }
  try {
    return switch (e.type) {
      SessionStarted.typeName => SessionStarted._fromJson(data),
      SessionCompleted.typeName => SessionCompleted._fromJson(data),
      SessionAbandoned.typeName => SessionAbandoned._fromJson(data),
      SuggestionShown.typeName => SuggestionShown._fromJson(data),
      SuggestionSkipped.typeName => SuggestionSkipped._fromJson(data),
      NudgeFired.typeName => NudgeFired._fromJson(data),
      NudgeDismissed.typeName => NudgeDismissed._fromJson(data),
      NudgeSnoozed.typeName => NudgeSnoozed._fromJson(data),
      TeachingPrepared.typeName => TeachingPrepared._fromJson(data),
      PaperAdded.typeName => PaperAdded._fromJson(data),
      PaperStatusChanged.typeName => PaperStatusChanged._fromJson(data),
      DeadlineAdded.typeName => DeadlineAdded._fromJson(data),
      DeadlineUpdated.typeName => DeadlineUpdated._fromJson(data),
      EnergyCheckin.typeName => EnergyCheckin._fromJson(data),
      _ => UnknownEvent(e.type, data),
    };
  } on ArgumentError catch (err) {
    throw FormatException('${e.type}: ${err.message}');
  }
}

/// Data of one event. Subclasses are value objects.
sealed class EventPayload {
  const EventPayload();

  String get type;
  Json toJson();

  @override
  bool operator ==(Object other) =>
      other is EventPayload &&
      other.type == type &&
      _jsonEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(type, toJson().length);

  @override
  String toString() => '$type ${toJson()}';
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_jsonEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// An event type this version does not know (e.g. from a newer app with the
/// same schema version). Kept in the log, ignored by the fold.
final class UnknownEvent extends EventPayload {
  const UnknownEvent(this.type, this.data);

  @override
  final String type;
  final Json data;

  @override
  Json toJson() => data;
}

// ---- Focus sessions ----

/// A focus session began.
final class SessionStarted extends EventPayload {
  SessionStarted({
    required this.sessionId,
    required this.activityId,
    required this.categoryId,
    required this.plannedMin,
    required DateTime start,
  }) : start = utcInstant(start) {
    if (plannedMin < 0) throw ArgumentError('plannedMin must be ≥ 0');
  }

  factory SessionStarted._fromJson(Json j) => SessionStarted(
    sessionId: j.req<String>('sessionId'),
    activityId: j.req<String>('activityId'),
    categoryId: j.req<String>('categoryId'),
    plannedMin: j.req<int>('plannedMin'),
    start: j.reqInstant('start'),
  );

  static const typeName = 'session.started';

  final String sessionId;
  final String activityId;
  final String categoryId;
  final int plannedMin;
  final DateTime start;

  @override
  String get type => typeName;

  @override
  Json toJson() => {
    'sessionId': sessionId,
    'activityId': activityId,
    'categoryId': categoryId,
    'plannedMin': plannedMin,
    'start': instantToJson(start),
  };
}

/// Shared shape of [SessionCompleted] and [SessionAbandoned]: each carries
/// the whole session, so it is meaningful even without its start event.
sealed class SessionEnded extends EventPayload {
  SessionEnded({
    required this.sessionId,
    required this.activityId,
    required this.categoryId,
    required DateTime start,
    required DateTime end,
    this.note,
  }) : start = utcInstant(start),
       end = utcInstant(end) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('Session $sessionId ends before it starts');
    }
  }

  final String sessionId;
  final String activityId;
  final String categoryId;
  final DateTime start;
  final DateTime end;
  final String? note;

  @override
  Json toJson() => {
    'sessionId': sessionId,
    'activityId': activityId,
    'categoryId': categoryId,
    'start': instantToJson(start),
    'end': instantToJson(end),
    if (note != null) 'note': note,
  };
}

/// A focus session ended with **Done**.
final class SessionCompleted extends SessionEnded {
  SessionCompleted({
    required super.sessionId,
    required super.activityId,
    required super.categoryId,
    required super.start,
    required super.end,
    super.note,
  });

  factory SessionCompleted._fromJson(Json j) => SessionCompleted(
    sessionId: j.req<String>('sessionId'),
    activityId: j.req<String>('activityId'),
    categoryId: j.req<String>('categoryId'),
    start: j.reqInstant('start'),
    end: j.reqInstant('end'),
    note: j.opt<String>('note'),
  );

  static const typeName = 'session.completed';

  @override
  String get type => typeName;
}

/// A focus session ended with **Abandon**.
final class SessionAbandoned extends SessionEnded {
  SessionAbandoned({
    required super.sessionId,
    required super.activityId,
    required super.categoryId,
    required super.start,
    required super.end,
    super.note,
  });

  factory SessionAbandoned._fromJson(Json j) => SessionAbandoned(
    sessionId: j.req<String>('sessionId'),
    activityId: j.req<String>('activityId'),
    categoryId: j.req<String>('categoryId'),
    start: j.reqInstant('start'),
    end: j.reqInstant('end'),
    note: j.opt<String>('note'),
  );

  static const typeName = 'session.abandoned';

  @override
  String get type => typeName;
}

// ---- Suggestions ----

/// The suggester showed an activity.
final class SuggestionShown extends EventPayload {
  const SuggestionShown({
    required this.activityId,
    required this.categoryId,
    this.freeMin,
  });

  factory SuggestionShown._fromJson(Json j) => SuggestionShown(
    activityId: j.req<String>('activityId'),
    categoryId: j.req<String>('categoryId'),
    freeMin: j.opt<int>('freeMin'),
  );

  static const typeName = 'suggestion.shown';

  final String activityId;
  final String categoryId;

  /// Length of the free block it was shown for.
  final int? freeMin;

  @override
  String get type => typeName;

  @override
  Json toJson() => {
    'activityId': activityId,
    'categoryId': categoryId,
    if (freeMin != null) 'freeMin': freeMin,
  };
}

/// The user asked for **Another one** instead of this activity.
final class SuggestionSkipped extends EventPayload {
  const SuggestionSkipped({required this.activityId, required this.categoryId});

  factory SuggestionSkipped._fromJson(Json j) => SuggestionSkipped(
    activityId: j.req<String>('activityId'),
    categoryId: j.req<String>('categoryId'),
  );

  static const typeName = 'suggestion.skipped';

  final String activityId;
  final String categoryId;

  @override
  String get type => typeName;

  @override
  Json toJson() => {'activityId': activityId, 'categoryId': categoryId};
}

// ---- Nudges ----

/// A nudge's notification was posted.
final class NudgeFired extends EventPayload {
  const NudgeFired({required this.nudgeId});

  factory NudgeFired._fromJson(Json j) =>
      NudgeFired(nudgeId: j.req<String>('nudgeId'));

  static const typeName = 'nudge.fired';
  final String nudgeId;

  @override
  String get type => typeName;

  @override
  Json toJson() => {'nudgeId': nudgeId};
}

/// The user dismissed a nudge.
final class NudgeDismissed extends EventPayload {
  const NudgeDismissed({required this.nudgeId});

  factory NudgeDismissed._fromJson(Json j) =>
      NudgeDismissed(nudgeId: j.req<String>('nudgeId'));

  static const typeName = 'nudge.dismissed';
  final String nudgeId;

  @override
  String get type => typeName;

  @override
  Json toJson() => {'nudgeId': nudgeId};
}

/// The user snoozed a nudge to a later free block.
final class NudgeSnoozed extends EventPayload {
  NudgeSnoozed({required this.nudgeId, required DateTime until})
    : until = utcInstant(until);

  factory NudgeSnoozed._fromJson(Json j) => NudgeSnoozed(
    nudgeId: j.req<String>('nudgeId'),
    until: j.reqInstant('until'),
  );

  static const typeName = 'nudge.snoozed';
  final String nudgeId;
  final DateTime until;

  @override
  String get type => typeName;

  @override
  Json toJson() => {'nudgeId': nudgeId, 'until': instantToJson(until)};
}

// ---- Teaching ----

/// One occurrence of a Teaching event was marked as prepared.
final class TeachingPrepared extends EventPayload {
  TeachingPrepared({required this.eventUid, required DateTime eventStart})
    : eventStart = utcInstant(eventStart);

  factory TeachingPrepared._fromJson(Json j) => TeachingPrepared(
    eventUid: j.req<String>('eventUid'),
    eventStart: j.reqInstant('eventStart'),
  );

  static const typeName = 'teaching.prepared';

  /// Calendar UID of the (possibly recurring) event.
  final String eventUid;

  /// Start of the prepared occurrence.
  final DateTime eventStart;

  @override
  String get type => typeName;

  @override
  Json toJson() => {
    'eventUid': eventUid,
    'eventStart': instantToJson(eventStart),
  };
}

// ---- Reading queue ----

/// Reading status of a paper.
enum PaperStatus { toRead, reading, read }

/// A paper entered the reading queue.
final class PaperAdded extends EventPayload {
  const PaperAdded({
    required this.paperId,
    required this.title,
    required this.source,
    this.doi,
    this.arxivId,
  });

  factory PaperAdded._fromJson(Json j) => PaperAdded(
    paperId: j.req<String>('paperId'),
    title: j.req<String>('title'),
    source: j.req<String>('source'),
    doi: j.opt<String>('doi'),
    arxivId: j.opt<String>('arxivId'),
  );

  static const typeName = 'paper.added';

  final String paperId;
  final String title;

  /// Where it came from, e.g. `zotero`, `arxiv`, `manual`.
  final String source;
  final String? doi;
  final String? arxivId;

  @override
  String get type => typeName;

  @override
  Json toJson() => {
    'paperId': paperId,
    'title': title,
    'source': source,
    if (doi != null) 'doi': doi,
    if (arxivId != null) 'arxivId': arxivId,
  };
}

/// A paper moved to another reading status.
final class PaperStatusChanged extends EventPayload {
  const PaperStatusChanged({
    required this.paperId,
    required this.status,
    this.note,
  });

  factory PaperStatusChanged._fromJson(Json j) => PaperStatusChanged(
    paperId: j.req<String>('paperId'),
    status: j.reqEnum('status', PaperStatus.values),
    note: j.opt<String>('note'),
  );

  static const typeName = 'paper.status_changed';

  final String paperId;
  final PaperStatus status;
  final String? note;

  @override
  String get type => typeName;

  @override
  Json toJson() => {
    'paperId': paperId,
    'status': status.name,
    if (note != null) 'note': note,
  };
}

// ---- Deadlines ----

/// A deadline was entered.
final class DeadlineAdded extends EventPayload {
  DeadlineAdded({
    required this.deadlineId,
    required this.title,
    required DateTime due,
    required this.hoursLeft,
    required this.categoryId,
  }) : due = utcInstant(due) {
    if (hoursLeft < 0) throw ArgumentError('hoursLeft must be ≥ 0');
  }

  factory DeadlineAdded._fromJson(Json j) => DeadlineAdded(
    deadlineId: j.req<String>('deadlineId'),
    title: j.req<String>('title'),
    due: j.reqInstant('due'),
    hoursLeft: j.reqDouble('hoursLeft'),
    categoryId: j.req<String>('categoryId'),
  );

  static const typeName = 'deadline.added';

  final String deadlineId;
  final String title;
  final DateTime due;

  /// Estimated hours of work left.
  final double hoursLeft;
  final String categoryId;

  @override
  String get type => typeName;

  @override
  Json toJson() => {
    'deadlineId': deadlineId,
    'title': title,
    'due': instantToJson(due),
    'hoursLeft': hoursLeft,
    'categoryId': categoryId,
  };
}

/// Some fields of a deadline changed; absent fields stay as they were.
final class DeadlineUpdated extends EventPayload {
  const DeadlineUpdated({
    required this.deadlineId,
    this.title,
    this.due,
    this.hoursLeft,
    this.categoryId,
    this.done,
  });

  factory DeadlineUpdated._fromJson(Json j) {
    final hours = j.opt<num>('hoursLeft')?.toDouble();
    if (hours != null && hours < 0) {
      throw ArgumentError('hoursLeft must be ≥ 0');
    }
    return DeadlineUpdated(
      deadlineId: j.req<String>('deadlineId'),
      title: j.opt<String>('title'),
      due: j.optInstant('due'),
      hoursLeft: hours,
      categoryId: j.opt<String>('categoryId'),
      done: j.opt<bool>('done'),
    );
  }

  static const typeName = 'deadline.updated';

  final String deadlineId;
  final String? title;
  final DateTime? due;
  final double? hoursLeft;
  final String? categoryId;
  final bool? done;

  @override
  String get type => typeName;

  @override
  Json toJson() => {
    'deadlineId': deadlineId,
    if (title != null) 'title': title,
    if (due != null) 'due': instantToJson(due!),
    if (hoursLeft != null) 'hoursLeft': hoursLeft,
    if (categoryId != null) 'categoryId': categoryId,
    if (done != null) 'done': done,
  };
}

// ---- Energy ----

/// The user reported their energy level.
final class EnergyCheckin extends EventPayload {
  const EnergyCheckin({required this.energy});

  factory EnergyCheckin._fromJson(Json j) =>
      EnergyCheckin(energy: j.reqEnum('energy', Energy.values));

  static const typeName = 'energy.checkin';
  final Energy energy;

  @override
  String get type => typeName;

  @override
  Json toJson() => {'energy': energy.name};
}
