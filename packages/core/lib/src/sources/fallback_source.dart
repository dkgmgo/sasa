import '../models/cal_event.dart';
import '../models/task_item.dart';
import 'calendar_source.dart';

/// Thrown by a [CalendarSource] that cannot serve a call right now (missing
/// permission, provider not installed, account not configured). Callers may
/// fall back to another source; other errors are real failures.
final class SourceUnavailable implements Exception {
  const SourceUnavailable(this.reason);

  /// Short, log-safe explanation (never contains credentials).
  final String reason;

  @override
  String toString() => 'SourceUnavailable: $reason';
}

/// Called when [FallbackSource] serves [operation] (`events` or `tasks`) from
/// the fallback.
typedef FallbackHandler = void Function(
  String operation,
  SourceUnavailable cause,
);

/// Uses [primary], and [fallback] for any call where [primary] throws
/// [SourceUnavailable]. Each call tries [primary] again, so re-granting a
/// permission takes effect without a restart.
final class FallbackSource implements CalendarSource {
  FallbackSource({
    required this.primary,
    required this.fallback,
    this.onFallback,
  });

  final CalendarSource primary;
  final CalendarSource fallback;
  final FallbackHandler? onFallback;

  @override
  Future<List<CalEvent>> events(DateTime from, DateTime to) async {
    try {
      return await primary.events(from, to);
    } on SourceUnavailable catch (e) {
      onFallback?.call('events', e);
      return fallback.events(from, to);
    }
  }

  @override
  Future<List<TaskItem>> tasks() async {
    try {
      return await primary.tasks();
    } on SourceUnavailable catch (e) {
      onFallback?.call('tasks', e);
      return fallback.tasks();
    }
  }
}

/// A [CalendarSource] that is never available, e.g. CalDAV before an account
/// is configured.
final class UnavailableSource implements CalendarSource {
  const UnavailableSource(this.reason);

  final String reason;

  @override
  Future<List<CalEvent>> events(DateTime from, DateTime to) =>
      Future.error(SourceUnavailable(reason));

  @override
  Future<List<TaskItem>> tasks() => Future.error(SourceUnavailable(reason));
}
