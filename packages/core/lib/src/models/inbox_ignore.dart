import '../json.dart';
import 'mapping_rule.dart';

/// A calendar or task list the user chose to hide from the Unclassified
/// inbox for now. Its items stay unclassified until a rule matches them.
///
/// Names compare like rules: trimmed and case-insensitive.
final class InboxIgnore {
  const InboxIgnore({required this.field, required this.name})
    : assert(
        field == MatchField.calendar || field == MatchField.list,
        'Only a calendar or a list can be ignored',
      );

  factory InboxIgnore.fromJson(Json json) {
    final field = json.reqEnum('field', MatchField.values);
    if (field != MatchField.calendar && field != MatchField.list) {
      throw FormatException('Only a calendar or a list can be ignored: $field');
    }
    return InboxIgnore(field: field, name: json.req<String>('name'));
  }

  /// [MatchField.calendar] or [MatchField.list].
  final MatchField field;
  final String name;

  String get _key => name.trim().toLowerCase();

  Json toJson() => {'field': field.name, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is InboxIgnore && other.field == field && other._key == _key;

  @override
  int get hashCode => Object.hash(field, _key);

  @override
  String toString() => 'InboxIgnore(${field.name} "$name")';
}
