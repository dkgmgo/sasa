import '../json.dart';
import '../models/local_time.dart';

/// Which days get a morning brief.
enum BriefDays {
  /// Monday to Friday.
  weekdays,

  /// All seven days.
  everyDay,
}

/// When the morning brief is sent. Part of `config.json`, so every device
/// sends it at the same local time.
final class BriefSettings {
  BriefSettings({
    this.enabled = true,
    required this.time,
    this.days = BriefDays.weekdays,
  }) {
    if (time.hour >= 24) throw ArgumentError('Brief time must be before 24:00');
  }

  /// On, at 07:30, Monday to Friday.
  factory BriefSettings.defaults() =>
      BriefSettings(time: const LocalTime(7, 30));

  factory BriefSettings.fromJson(Json json) {
    final time = LocalTime.parse(json.req<String>('time'));
    if (time.hour >= 24) {
      throw const FormatException('Brief time must be before 24:00');
    }
    return BriefSettings(
      enabled: json.req<bool>('enabled'),
      time: time,
      days: json.reqEnum('days', BriefDays.values),
    );
  }

  final bool enabled;

  /// Local time (in the configured zone) at which the brief is sent.
  final LocalTime time;
  final BriefDays days;

  /// True when a brief is sent on [weekday] (`DateTime.monday` …
  /// `DateTime.sunday`).
  bool occursOn(int weekday) =>
      enabled &&
      switch (days) {
        BriefDays.weekdays => weekday <= DateTime.friday,
        BriefDays.everyDay => true,
      };

  BriefSettings copyWith({bool? enabled, LocalTime? time, BriefDays? days}) =>
      BriefSettings(
        enabled: enabled ?? this.enabled,
        time: time ?? this.time,
        days: days ?? this.days,
      );

  Json toJson() => {'enabled': enabled, 'time': '$time', 'days': days.name};

  @override
  bool operator ==(Object other) =>
      other is BriefSettings &&
      other.enabled == enabled &&
      other.time == time &&
      other.days == days;

  @override
  int get hashCode => Object.hash(enabled, time, days);

  @override
  String toString() => 'BriefSettings(${toJson()})';
}
