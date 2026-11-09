import 'models/cal_event.dart';
import 'models/category.dart';
import 'models/energy.dart';
import 'models/mapping_rule.dart';
import 'models/task_item.dart';

/// Result of a rule match, with defaults filled in from the category.
final class Classification {
  const Classification({
    required this.categoryId,
    required this.durationMin,
    required this.energy,
    required this.rule,
  });

  final String categoryId;

  /// The rule's override, else the category's default duration.
  final int durationMin;

  /// The rule's override, else the category's default energy.
  final Energy energy;

  /// The rule that matched.
  final MappingRule rule;
}

/// An item together with its classification.
final class Classified<T> {
  const Classified(this.item, this.classification);
  final T item;
  final Classification classification;
}

/// Items split into classified ones and the "Unclassified" inbox.
final class CategorisedBatch<T> {
  CategorisedBatch(List<Classified<T>> classified, List<T> unclassified)
    : classified = List.unmodifiable(classified),
      unclassified = List.unmodifiable(unclassified);

  final List<Classified<T>> classified;
  final List<T> unclassified;
}

/// Maps events and tasks to categories with [MappingRule]s.
///
/// Rules are tried from the highest priority down, ties in list order; the
/// first match wins. Rules whose category no longer exists, and title rules
/// whose regular expression is invalid, never match.
final class Categoriser {
  Categoriser({
    required List<MappingRule> rules,
    required List<Category> categories,
  }) : _categories = {for (final c in categories) c.id: c},
       _rules = _compile(rules);

  final Map<String, Category> _categories;
  final List<_CompiledRule> _rules;

  static List<_CompiledRule> _compile(List<MappingRule> rules) => [
    for (final r in evaluationOrder(rules)) _CompiledRule(r),
  ];

  /// [rules] in the order they are tried: highest priority first, ties in
  /// list order.
  static List<MappingRule> evaluationOrder(List<MappingRule> rules) {
    final indexed = [for (var i = 0; i < rules.length; i++) (i, rules[i])]
      ..sort((a, b) {
        // List.sort is not stable: break ties on the original index.
        final byPriority = b.$2.priority.compareTo(a.$2.priority);
        return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
      });
    return [for (final (_, r) in indexed) r];
  }

  /// Classification for [event], or null if it belongs in the inbox.
  Classification? classifyEvent(CalEvent event) => _first(
    (r) => switch (r.rule.field) {
      MatchField.calendar => _sameName(event.calendarName, r.rule.pattern),
      MatchField.titleRegex => r.matchesTitle(event.title),
      MatchField.list || MatchField.tag => false,
    },
  );

  /// Classification for [task], or null if it belongs in the inbox.
  Classification? classifyTask(TaskItem task) => _first(
    (r) => switch (r.rule.field) {
      MatchField.list => _sameName(task.listName, r.rule.pattern),
      MatchField.tag => task.tags.any((t) => _sameName(t, r.rule.pattern)),
      MatchField.titleRegex => r.matchesTitle(task.title),
      MatchField.calendar => false,
    },
  );

  CategorisedBatch<CalEvent> events(Iterable<CalEvent> events) =>
      _batch(events, classifyEvent);

  CategorisedBatch<TaskItem> tasks(Iterable<TaskItem> tasks) =>
      _batch(tasks, classifyTask);

  CategorisedBatch<T> _batch<T>(
    Iterable<T> items,
    Classification? Function(T) classify,
  ) {
    final hit = <Classified<T>>[];
    final miss = <T>[];
    for (final item in items) {
      final c = classify(item);
      c == null ? miss.add(item) : hit.add(Classified(item, c));
    }
    return CategorisedBatch(hit, miss);
  }

  Classification? _first(bool Function(_CompiledRule) matches) {
    for (final r in _rules) {
      final category = _categories[r.rule.categoryId];
      if (category == null || !matches(r)) continue;
      return Classification(
        categoryId: category.id,
        durationMin: r.rule.durationMin ?? category.defaultDurationMin,
        energy: r.rule.energy ?? category.defaultEnergy,
        rule: r.rule,
      );
    }
    return null;
  }

  static bool _sameName(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
}

final class _CompiledRule {
  _CompiledRule(this.rule) : _regex = _tryRegex(rule);

  final MappingRule rule;
  final RegExp? _regex;

  static RegExp? _tryRegex(MappingRule rule) {
    if (rule.field != MatchField.titleRegex) return null;
    try {
      return RegExp(rule.pattern, caseSensitive: false, unicode: true);
    } on FormatException {
      return null;
    }
  }

  bool matchesTitle(String title) => _regex?.hasMatch(title) ?? false;
}

/// One-tap rule from the inbox: "everything in this calendar -> category".
MappingRule ruleForEvent(
  CalEvent event, {
  required String categoryId,
  int priority = 0,
}) => MappingRule(
  field: MatchField.calendar,
  pattern: event.calendarName,
  categoryId: categoryId,
  priority: priority,
);

/// One-tap rule from the inbox: "everything in this list -> category".
MappingRule ruleForTask(
  TaskItem task, {
  required String categoryId,
  int priority = 0,
}) => MappingRule(
  field: MatchField.list,
  pattern: task.listName,
  categoryId: categoryId,
  priority: priority,
);
