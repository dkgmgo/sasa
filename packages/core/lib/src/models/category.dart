import '../json.dart';
import 'energy.dart';
import 'local_time.dart';

/// A user-defined bucket of time (Reading, Research, …).
final class Category {
  const Category({
    required this.id,
    required this.name,
    required this.color,
    required this.weeklyTargetMin,
    required this.defaultEnergy,
    required this.defaultDurationMin,
    this.preferredWindow,
  });

  factory Category.fromJson(Json json) => Category(
    id: json.req<String>('id'),
    name: json.req<String>('name'),
    color: json.req<String>('color'),
    weeklyTargetMin: json.req<int>('weeklyTargetMin'),
    defaultEnergy: json.reqEnum('defaultEnergy', Energy.values),
    defaultDurationMin: json.req<int>('defaultDurationMin'),
    preferredWindow: switch (json.optObject('preferredWindow')) {
      null => null,
      final w => TimeWindow.fromJson(w),
    },
  );

  final String id;
  final String name;

  /// `#RRGGBB`.
  final String color;
  final int weeklyTargetMin;
  final Energy defaultEnergy;
  final int defaultDurationMin;

  /// Time of day this category fits best, e.g. research 09:00–12:00.
  final TimeWindow? preferredWindow;

  Category copyWith({
    String? name,
    String? color,
    int? weeklyTargetMin,
    Energy? defaultEnergy,
    int? defaultDurationMin,
    TimeWindow? preferredWindow,
    bool clearPreferredWindow = false,
  }) => Category(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    weeklyTargetMin: weeklyTargetMin ?? this.weeklyTargetMin,
    defaultEnergy: defaultEnergy ?? this.defaultEnergy,
    defaultDurationMin: defaultDurationMin ?? this.defaultDurationMin,
    preferredWindow: clearPreferredWindow
        ? null
        : preferredWindow ?? this.preferredWindow,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'weeklyTargetMin': weeklyTargetMin,
    'defaultEnergy': defaultEnergy.name,
    'defaultDurationMin': defaultDurationMin,
    if (preferredWindow != null) 'preferredWindow': preferredWindow!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Category &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.weeklyTargetMin == weeklyTargetMin &&
      other.defaultEnergy == defaultEnergy &&
      other.defaultDurationMin == defaultDurationMin &&
      other.preferredWindow == preferredWindow;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    color,
    weeklyTargetMin,
    defaultEnergy,
    defaultDurationMin,
    preferredWindow,
  );

  @override
  String toString() => 'Category($id)';
}
