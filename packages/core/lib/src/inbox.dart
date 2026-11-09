import 'categoriser.dart';
import 'config/app_config.dart';
import 'models/cal_event.dart';
import 'models/category.dart';
import 'models/energy.dart';
import 'models/inbox_ignore.dart';
import 'models/mapping_rule.dart';
import 'models/task_item.dart';

/// Unclassified items that share a calendar (events) or a list (tasks), so
/// one rule can classify them all.
final class InboxGroup {
  InboxGroup._(
    this.field,
    this.name,
    List<CalEvent> events,
    List<TaskItem> tasks,
  ) : events = List.unmodifiable(events),
      tasks = List.unmodifiable(tasks);

  /// [MatchField.calendar] for events, [MatchField.list] for tasks.
  final MatchField field;

  /// Calendar or list name, as first seen.
  final String name;

  /// Distinct events (one per uid, the earliest instance), by start.
  final List<CalEvent> events;

  /// Open tasks, in source order.
  final List<TaskItem> tasks;

  int get count => events.length + tasks.length;

  /// What to store to hide this group from the inbox.
  InboxIgnore get ignoreKey => InboxIgnore(field: field, name: name);

  /// "Everything in this calendar / list → [categoryId]".
  MappingRule ruleFor(String categoryId) =>
      MappingRule(field: field, pattern: name, categoryId: categoryId);
}

/// The "Unclassified" inbox: events and open tasks no rule matches.
final class Inbox {
  Inbox._(List<InboxGroup> groups, List<InboxGroup> ignored)
    : groups = List.unmodifiable(groups),
      ignored = List.unmodifiable(ignored);

  /// Largest group first, then by name. Ignored groups are not included.
  final List<InboxGroup> groups;

  /// Groups the user hid for now (see `AppConfig.inboxIgnored`), same order.
  /// They do not count in [itemCount] or [isEmpty].
  final List<InboxGroup> ignored;

  int get itemCount => groups.fold(0, (n, g) => n + g.count);
  bool get isEmpty => groups.isEmpty;
}

/// Groups the items of [events] and [tasks] that [config]'s rules leave
/// unclassified. Completed tasks are left out. Names are grouped the way
/// rules compare them (trimmed, case-insensitive).
Inbox buildInbox({
  required AppConfig config,
  required Iterable<CalEvent> events,
  required Iterable<TaskItem> tasks,
}) {
  final categoriser = Categoriser(
    rules: config.rules,
    categories: config.categories,
  );
  final calendars = <String, (String, Map<String, CalEvent>)>{};
  for (final e in categoriser.events(events).unclassified) {
    final g = calendars.putIfAbsent(
      _key(e.calendarName),
      () => (e.calendarName, {}),
    );
    final seen = g.$2[e.uid];
    if (seen == null || e.start.isBefore(seen.start)) g.$2[e.uid] = e;
  }
  final lists = <String, (String, List<TaskItem>)>{};
  for (final t
      in categoriser.tasks(tasks.where((t) => !t.completed)).unclassified) {
    lists.putIfAbsent(_key(t.listName), () => (t.listName, [])).$2.add(t);
  }
  final groups =
      [
        for (final (name, byUid) in calendars.values)
          InboxGroup._(
            MatchField.calendar,
            name,
            byUid.values.toList()..sort((a, b) => a.start.compareTo(b.start)),
            const [],
          ),
        for (final (name, items) in lists.values)
          InboxGroup._(MatchField.list, name, const [], items),
      ]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        final byName = _key(a.name).compareTo(_key(b.name));
        return byName != 0 ? byName : a.field.index.compareTo(b.field.index);
      });
  final hidden = config.inboxIgnored.toSet();
  return Inbox._(
    [
      for (final g in groups)
        if (!hidden.contains(g.ignoreKey)) g,
    ],
    [
      for (final g in groups)
        if (hidden.contains(g.ignoreKey)) g,
    ],
  );
}

String _key(String name) => name.trim().toLowerCase();

/// Default priority of a quick rule on a calendar or list.
const int containerRulePriority = 0;

/// Default priority of a quick tag rule: beats calendar and list rules.
const int tagRulePriority = 5;

/// Default priority of a quick title rule: the most specific.
const int titleRulePriority = 10;

/// A rule matching exactly [title] (trimmed), case-insensitively.
MappingRule ruleForTitle(
  String title, {
  required String categoryId,
  int priority = titleRulePriority,
}) => MappingRule(
  field: MatchField.titleRegex,
  pattern: '^${RegExp.escape(title.trim())}\$',
  categoryId: categoryId,
  priority: priority,
);

/// A rule matching tasks tagged [tag].
MappingRule ruleForTag(
  String tag, {
  required String categoryId,
  int priority = tagRulePriority,
}) => MappingRule(
  field: MatchField.tag,
  pattern: tag,
  categoryId: categoryId,
  priority: priority,
);

/// Quick rules that would classify [event], broadest first.
List<MappingRule> ruleChoicesForEvent(
  CalEvent event, {
  required String categoryId,
}) => [
  ruleForEvent(event, categoryId: categoryId),
  ruleForTitle(event.title, categoryId: categoryId),
];

/// Quick rules that would classify [task], broadest first.
List<MappingRule> ruleChoicesForTask(
  TaskItem task, {
  required String categoryId,
}) => [
  ruleForTask(task, categoryId: categoryId),
  for (final tag in task.tags) ruleForTag(tag, categoryId: categoryId),
  ruleForTitle(task.title, categoryId: categoryId),
];

/// The items one rule matches, for a live preview while editing it.
final class RulePreview {
  RulePreview._(List<CalEvent> events, List<TaskItem> tasks)
    : events = List.unmodifiable(events),
      tasks = List.unmodifiable(tasks);

  /// Distinct events (one per uid, first seen).
  final List<CalEvent> events;

  /// Open tasks.
  final List<TaskItem> tasks;

  int get count => events.length + tasks.length;
}

/// What [rule] alone would match among [events] and the open [tasks],
/// whatever other rules say and whether or not its category exists.
RulePreview previewRule(
  MappingRule rule, {
  required Iterable<CalEvent> events,
  required Iterable<TaskItem> tasks,
}) {
  final c = Categoriser(
    rules: [rule],
    categories: [
      Category(
        id: rule.categoryId,
        name: '',
        color: '#000000',
        weeklyTargetMin: 0,
        defaultEnergy: Energy.low,
        defaultDurationMin: 1,
      ),
    ],
  );
  final seen = <String>{};
  return RulePreview._(
    [
      for (final e in events)
        if (c.classifyEvent(e) != null && seen.add(e.uid)) e,
    ],
    [
      for (final t in tasks)
        if (!t.completed && c.classifyTask(t) != null) t,
    ],
  );
}
