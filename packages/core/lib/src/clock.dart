/// Source of the current time. Core code never reads the system clock
/// directly: it receives a [Clock], so tests can pin and move time.
abstract interface class Clock {
  /// The current instant, always in UTC.
  DateTime now();
}

/// A [Clock] backed by a function, e.g. `FunctionClock(DateTime.now)` in the
/// app or CLI.
final class FunctionClock implements Clock {
  FunctionClock(this._now);

  final DateTime Function() _now;

  @override
  DateTime now() => _now().toUtc();
}

/// A manually driven [Clock] for tests.
final class FakeClock implements Clock {
  FakeClock(DateTime start) : _now = start.toUtc();

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Moves time forward (or backward with a negative duration).
  void advance(Duration d) => _now = _now.add(d);

  /// Jumps to [instant].
  void set(DateTime instant) => _now = instant.toUtc();
}
