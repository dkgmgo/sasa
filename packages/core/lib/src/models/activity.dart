import '../json.dart';
import '../time_zones.dart';
import 'energy.dart';

/// Where a suggestion candidate came from.
enum ActivitySource { task, nudge, template, teachingPrep, deadline, paper }

/// Something the suggester can propose for a free block.
final class Activity {
  Activity({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.durationMin,
    required this.energy,
    required this.source,
    DateTime? due,
    this.refId,
  }) : due = due == null ? null : utcInstant(due);

  factory Activity.fromJson(Json json) => Activity(
    id: json.req<String>('id'),
    title: json.req<String>('title'),
    categoryId: json.req<String>('categoryId'),
    durationMin: json.req<int>('durationMin'),
    energy: json.reqEnum('energy', Energy.values),
    source: json.reqEnum('source', ActivitySource.values),
    due: json.optInstant('due'),
    refId: json.opt<String>('refId'),
  );

  final String id;
  final String title;
  final String categoryId;
  final int durationMin;
  final Energy energy;
  final ActivitySource source;
  final DateTime? due;

  /// Id of the underlying item (task uid, nudge id, paper id, …).
  final String? refId;

  Json toJson() => {
    'id': id,
    'title': title,
    'categoryId': categoryId,
    'durationMin': durationMin,
    'energy': energy.name,
    'source': source.name,
    if (due != null) 'due': instantToJson(due!),
    if (refId != null) 'refId': refId,
  };

  @override
  bool operator ==(Object other) =>
      other is Activity &&
      other.id == id &&
      other.title == title &&
      other.categoryId == categoryId &&
      other.durationMin == durationMin &&
      other.energy == energy &&
      other.source == source &&
      other.due == due &&
      other.refId == refId;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    categoryId,
    durationMin,
    energy,
    source,
    due,
    refId,
  );

  @override
  String toString() => 'Activity($id, "$title")';
}
