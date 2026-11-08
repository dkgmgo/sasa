import '../json.dart';
import 'energy.dart';

/// What a [MappingRule] looks at.
enum MatchField {
  /// Event calendar name (events only), case-insensitive equality.
  calendar,

  /// Task list name (tasks only), case-insensitive equality.
  list,

  /// Any task tag (tasks only), case-insensitive equality.
  tag,

  /// Title of an event or task, case-insensitive regular expression search.
  titleRegex,
}

/// Maps calendar events or tasks to a category, inside the app only.
///
/// Rules are tried from the highest [priority] down; among equal priorities
/// the earlier rule in the list wins. The first match decides.
final class MappingRule {
  const MappingRule({
    required this.field,
    required this.pattern,
    required this.categoryId,
    this.priority = 0,
    this.durationMin,
    this.energy,
  });

  factory MappingRule.fromJson(Json json) => MappingRule(
    field: json.reqEnum('field', MatchField.values),
    pattern: json.req<String>('pattern'),
    categoryId: json.req<String>('categoryId'),
    priority: json.req<int>('priority'),
    durationMin: json.opt<int>('durationMin'),
    energy: json.optEnum('energy', Energy.values),
  );

  final MatchField field;
  final String pattern;
  final String categoryId;
  final int priority;

  /// Overrides the category's default duration.
  final int? durationMin;

  /// Overrides the category's default energy.
  final Energy? energy;

  Json toJson() => {
    'field': field.name,
    'pattern': pattern,
    'categoryId': categoryId,
    'priority': priority,
    if (durationMin != null) 'durationMin': durationMin,
    if (energy != null) 'energy': energy!.name,
  };

  @override
  bool operator ==(Object other) =>
      other is MappingRule &&
      other.field == field &&
      other.pattern == pattern &&
      other.categoryId == categoryId &&
      other.priority == priority &&
      other.durationMin == durationMin &&
      other.energy == energy;

  @override
  int get hashCode =>
      Object.hash(field, pattern, categoryId, priority, durationMin, energy);

  @override
  String toString() =>
      'MappingRule(${field.name} "$pattern" → $categoryId, p$priority)';
}
