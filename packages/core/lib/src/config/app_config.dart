import '../clock.dart';
import '../free_blocks.dart';
import '../json.dart';
import '../models/category.dart';
import '../models/mapping_rule.dart';
import '../models/nudge.dart';
import '../time_zones.dart';
import 'defaults.dart';
import 'suggester_weights.dart';

/// Thrown when `config.json` was written by a newer app version.
final class UnsupportedConfigVersion implements Exception {
  const UnsupportedConfigVersion(this.found, this.supported);
  final int found;
  final int supported;

  @override
  String toString() =>
      'UnsupportedConfigVersion: config.json is version $found, '
      'this app supports up to $supported. Update the app.';
}

/// Contents of `config.json` in the synced folder.
///
/// Last writer wins, using [updatedAt]. Holds no secrets.
final class AppConfig {
  AppConfig({
    required DateTime updatedAt,
    required this.timeZone,
    required this.freeBlocks,
    required List<Category> categories,
    required List<MappingRule> rules,
    required List<Nudge> nudges,
    required this.weights,
  }) : updatedAt = utcInstant(updatedAt),
       categories = List.unmodifiable(categories),
       rules = List.unmodifiable(rules),
       nudges = List.unmodifiable(nudges) {
    final ids = <String>{};
    for (final c in categories) {
      if (!ids.add(c.id)) throw ArgumentError('Duplicate category id ${c.id}');
    }
  }

  /// Fresh configuration with the default categories and settings.
  factory AppConfig.defaults({required Clock clock}) => AppConfig(
    updatedAt: clock.now(),
    timeZone: defaultTimeZone,
    freeBlocks: FreeBlockSettings.defaults(),
    categories: defaultCategories(),
    rules: const [],
    nudges: const [],
    weights: const SuggesterWeights(),
  );

  /// Parses `config.json`, migrating older versions.
  ///
  /// Throws [UnsupportedConfigVersion] for a newer version and
  /// [FormatException] for anything malformed. Unknown keys are ignored.
  factory AppConfig.fromJson(Json json) {
    final version = json.req<int>('version');
    if (version < 1) throw FormatException('Invalid config version $version');
    if (version > currentVersion) {
      throw UnsupportedConfigVersion(version, currentVersion);
    }
    var data = json;
    for (var v = version; v < currentVersion; v++) {
      data = _migrations[v]!(data);
    }
    final categories = data.reqList(
      'categories',
      (e) => Category.fromJson(asJson(e)),
    );
    final ids = <String>{};
    for (final c in categories) {
      if (!ids.add(c.id)) {
        throw FormatException('Duplicate category id ${c.id}');
      }
    }
    return AppConfig(
      updatedAt: data.reqInstant('updatedAt'),
      timeZone: data.req<String>('timeZone'),
      freeBlocks: FreeBlockSettings.fromJson(data.reqObject('freeBlocks')),
      categories: categories,
      rules: data.reqList('rules', (e) => MappingRule.fromJson(asJson(e))),
      nudges: data.reqList('nudges', (e) => Nudge.fromJson(asJson(e))),
      weights: SuggesterWeights.fromJson(data.reqObject('weights')),
    );
  }

  /// Schema version written by this code.
  static const int currentVersion = 1;

  /// `_migrations[n]` turns a version-n document into version n+1.
  static final Map<int, Json Function(Json)> _migrations = {};

  int get version => currentVersion;
  final DateTime updatedAt;

  /// IANA zone used to interpret working hours and windows.
  final String timeZone;
  final FreeBlockSettings freeBlocks;
  final List<Category> categories;
  final List<MappingRule> rules;
  final List<Nudge> nudges;
  final SuggesterWeights weights;

  Category? categoryById(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  AppConfig copyWith({
    DateTime? updatedAt,
    String? timeZone,
    FreeBlockSettings? freeBlocks,
    List<Category>? categories,
    List<MappingRule>? rules,
    List<Nudge>? nudges,
    SuggesterWeights? weights,
  }) => AppConfig(
    updatedAt: updatedAt ?? this.updatedAt,
    timeZone: timeZone ?? this.timeZone,
    freeBlocks: freeBlocks ?? this.freeBlocks,
    categories: categories ?? this.categories,
    rules: rules ?? this.rules,
    nudges: nudges ?? this.nudges,
    weights: weights ?? this.weights,
  );

  Json toJson() => {
    'version': version,
    'updatedAt': instantToJson(updatedAt),
    'timeZone': timeZone,
    'freeBlocks': freeBlocks.toJson(),
    'categories': [for (final c in categories) c.toJson()],
    'rules': [for (final r in rules) r.toJson()],
    'nudges': [for (final n in nudges) n.toJson()],
    'weights': weights.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is AppConfig &&
      other.updatedAt == updatedAt &&
      other.timeZone == timeZone &&
      other.freeBlocks == freeBlocks &&
      listEquals(other.categories, categories) &&
      listEquals(other.rules, rules) &&
      listEquals(other.nudges, nudges) &&
      other.weights == weights;

  @override
  int get hashCode => Object.hash(
    updatedAt,
    timeZone,
    freeBlocks,
    Object.hashAll(categories),
    Object.hashAll(rules),
    Object.hashAll(nudges),
    weights,
  );
}
