import '../clock.dart';
import '../models/category.dart';
import '../models/inbox_ignore.dart';
import '../models/mapping_rule.dart';
import 'app_config.dart';

/// A change to the configuration, as a pure function.
///
/// Edits are functions, not finished configs, so the app can re-read
/// `config.json` just before saving and apply the edit to the newest version:
/// a change made meanwhile on another device is kept.
typedef ConfigEdit = AppConfig Function(AppConfig config);

/// Thrown by an edit whose target is no longer in the configuration, e.g. a
/// rule that another device changed or removed.
final class ConfigEditConflict implements Exception {
  const ConfigEditConflict(this.message);
  final String message;

  @override
  String toString() => 'ConfigEditConflict: $message';
}

/// Applies [edit] to [base] and stamps the result's `updatedAt`.
///
/// The stamp is the clock's time, or just after [base]'s when the clock is
/// behind (another device's clock was ahead): an edit always counts as the
/// newest version under last-writer-wins.
AppConfig applyConfigEdit(AppConfig base, ConfigEdit edit, Clock clock) {
  final now = clock.now();
  final floor = base.updatedAt.add(const Duration(milliseconds: 1));
  return edit(base).copyWith(updatedAt: now.isAfter(floor) ? now : floor);
}

/// The edits the settings screens make.
abstract final class ConfigEdits {
  /// Appends [rule]; does nothing when an identical rule exists.
  static ConfigEdit addRule(MappingRule rule) =>
      (c) => c.rules.contains(rule) ? c : c.copyWith(rules: [...c.rules, rule]);

  /// Replaces the first rule equal to [old] with [updated], in place.
  static ConfigEdit replaceRule(MappingRule old, MappingRule updated) => (c) {
    final i = _indexOf(c, old);
    return c.copyWith(rules: [...c.rules]..[i] = updated);
  };

  /// Removes the first rule equal to [rule].
  static ConfigEdit removeRule(MappingRule rule) => (c) {
    final i = _indexOf(c, rule);
    return c.copyWith(rules: [...c.rules]..removeAt(i));
  };

  /// Replaces the category with the same id, or appends [category].
  static ConfigEdit putCategory(Category category) => (c) {
    final i = c.categories.indexWhere((x) => x.id == category.id);
    return c.copyWith(
      categories: i < 0
          ? [...c.categories, category]
          : ([...c.categories]..[i] = category),
    );
  };

  /// Removes the category [id] and every rule that points at it.
  static ConfigEdit removeCategory(String id) => (c) {
    if (c.categoryById(id) == null) {
      throw ConfigEditConflict('Category $id no longer exists');
    }
    return c.copyWith(
      categories: [
        for (final x in c.categories)
          if (x.id != id) x,
      ],
      rules: [
        for (final r in c.rules)
          if (r.categoryId != id) r,
      ],
    );
  };

  /// Hides a calendar or list from the inbox; does nothing when hidden.
  static ConfigEdit ignoreInInbox(InboxIgnore ignore) =>
      (c) => c.inboxIgnored.contains(ignore)
      ? c
      : c.copyWith(inboxIgnored: [...c.inboxIgnored, ignore]);

  /// Shows a calendar or list in the inbox again; does nothing when shown.
  static ConfigEdit unignoreInInbox(InboxIgnore ignore) =>
      (c) => c.copyWith(
        inboxIgnored: [
          for (final i in c.inboxIgnored)
            if (i != ignore) i,
        ],
      );

  static int _indexOf(AppConfig c, MappingRule rule) {
    final i = c.rules.indexOf(rule);
    if (i < 0) throw ConfigEditConflict('Rule $rule no longer exists');
    return i;
  }
}

const _folded = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', //
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', //
  'æ': 'ae', 'œ': 'oe', 'ß': 'ss',
};

/// A stable id for a new category called [name]: a lower-case ASCII slug,
/// suffixed `-2`, `-3`… when taken.
String newCategoryId(AppConfig config, String name) {
  final buf = StringBuffer();
  for (final ch in name.toLowerCase().split('')) {
    buf.write(_folded[ch] ?? ch);
  }
  final slug = buf
      .toString()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final stem = slug.isEmpty ? 'category' : slug;
  final taken = {for (final c in config.categories) c.id};
  if (!taken.contains(stem)) return stem;
  for (var n = 2; ; n++) {
    if (!taken.contains('$stem-$n')) return '$stem-$n';
  }
}

/// Why a category cannot be saved.
enum CategoryProblem {
  emptyName('Give it a name.'),
  duplicateName('Another category has this name.'),
  badColor('Pick a colour.'),
  negativeTarget('The weekly target cannot be negative.'),
  badDuration('The default duration must be 1 min to 24 h.');

  const CategoryProblem(this.message);
  final String message;
}

/// Problems with [category] as it would be saved into [config] (where a
/// category with the same id is the one being edited).
Set<CategoryProblem> categoryProblems(Category category, AppConfig config) {
  final name = category.name.trim().toLowerCase();
  return {
    if (name.isEmpty) CategoryProblem.emptyName,
    if (name.isNotEmpty &&
        config.categories.any(
          (c) => c.id != category.id && c.name.trim().toLowerCase() == name,
        ))
      CategoryProblem.duplicateName,
    if (parseHexColor(category.color) == null) CategoryProblem.badColor,
    if (category.weeklyTargetMin < 0) CategoryProblem.negativeTarget,
    if (category.defaultDurationMin < 1 || category.defaultDurationMin > 1440)
      CategoryProblem.badDuration,
  };
}

/// Why a rule cannot be saved.
enum RuleProblem {
  emptyPattern('Enter what to match.'),
  badRegex('This is not a valid regular expression.'),
  unknownCategory('Choose a category.'),
  badDuration('The duration must be 1 min to 24 h.');

  const RuleProblem(this.message);
  final String message;
}

/// Problems with [rule] in [config].
Set<RuleProblem> ruleProblems(MappingRule rule, AppConfig config) {
  final empty = rule.pattern.trim().isEmpty;
  final d = rule.durationMin;
  return {
    if (empty) RuleProblem.emptyPattern,
    if (!empty &&
        rule.field == MatchField.titleRegex &&
        !_isRegex(rule.pattern))
      RuleProblem.badRegex,
    if (config.categoryById(rule.categoryId) == null)
      RuleProblem.unknownCategory,
    if (d != null && (d < 1 || d > 1440)) RuleProblem.badDuration,
  };
}

bool _isRegex(String pattern) {
  try {
    RegExp(pattern, unicode: true);
    return true;
  } on FormatException {
    return false;
  }
}

/// `#RRGGBB` as opaque ARGB (`0xFFRRGGBB`), or null when malformed.
int? parseHexColor(String color) {
  if (!_hex.hasMatch(color)) return null;
  return 0xFF000000 | int.parse(color.substring(1), radix: 16);
}

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Colours offered for categories: coastal tones, the defaults first.
const List<String> categoryPalette = [
  '#FF7A5C', // Coral
  '#F3E3C3', // Sand
  '#0B7474', // Ocean
  '#FFC9B8', // Peach
  '#BDE7EC', // Sky
  '#0E3B43', // Deep
  '#5CC2BC', // Lagoon
  '#D9B77E', // Dune
  '#E0563F', // Reef
  '#3F7A5A', // Mangrove
  '#E8D5E8', // Shell
  '#2B4C7E', // Night
];
