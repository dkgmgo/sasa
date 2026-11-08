/// Small, strict helpers for reading decoded JSON. Internal to core.
///
/// Every failure is a [FormatException] naming the offending key, so a
/// hand-edited or corrupted file gives a readable error instead of a
/// `TypeError` deep inside a constructor.
library;

typedef Json = Map<String, Object?>;

extension JsonRead on Json {
  /// Required value of type [T].
  T req<T extends Object>(String key) {
    final v = this[key];
    if (v is T) return v;
    if (v == null) throw FormatException('Missing required key "$key"');
    throw FormatException('Key "$key" has the wrong type: $v');
  }

  /// Optional value of type [T]: null when absent or null.
  T? opt<T extends Object>(String key) {
    final v = this[key];
    if (v == null || v is T) return v as T?;
    throw FormatException('Key "$key" has the wrong type: $v');
  }

  /// Required number as a double (JSON may encode `1.0` as `1`).
  double reqDouble(String key) => req<num>(key).toDouble();

  /// Required nested object.
  Json reqObject(String key) => asJson(req<Object>(key), key);

  /// Optional nested object.
  Json? optObject(String key) {
    final v = opt<Object>(key);
    return v == null ? null : asJson(v, key);
  }

  /// Required list, each element converted with [f].
  List<T> reqList<T>(String key, T Function(Object? e) f) =>
      List.unmodifiable(req<List<Object?>>(key).map(f));

  /// Required instant. Must carry `Z` or an explicit offset, so parsing never
  /// depends on the machine's local time zone.
  DateTime reqInstant(String key) => parseInstant(req<String>(key), key);

  /// Optional instant, same rules as [reqInstant].
  DateTime? optInstant(String key) {
    final v = opt<String>(key);
    return v == null ? null : parseInstant(v, key);
  }

  /// Required enum value stored by name.
  T reqEnum<T extends Enum>(String key, List<T> values) =>
      enumByName(values, req<String>(key), key);

  /// Optional enum value stored by name.
  T? optEnum<T extends Enum>(String key, List<T> values) {
    final v = opt<String>(key);
    return v == null ? null : enumByName(values, v, key);
  }
}

/// Casts [v] to a JSON object or throws a [FormatException].
Json asJson(Object? v, [String what = 'value']) {
  if (v is Map<String, Object?>) return v;
  throw FormatException('Expected an object for "$what": $v');
}

/// Parses an ISO-8601 instant with an explicit offset into UTC.
DateTime parseInstant(String s, [String what = 'timestamp']) {
  final d = DateTime.tryParse(s);
  if (d == null) throw FormatException('Invalid timestamp for "$what": $s');
  if (!d.isUtc) {
    throw FormatException('Timestamp for "$what" has no UTC offset: $s');
  }
  return d;
}

/// Looks up an enum value by name, as a [FormatException] on failure.
T enumByName<T extends Enum>(List<T> values, String name, [String what = '']) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('Unknown value for "$what": $name');
}

/// Serialises an instant as ISO-8601 UTC.
String instantToJson(DateTime d) => d.toUtc().toIso8601String();

/// Element-wise list equality.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Map equality with element-wise list values.
bool mapOfListsEquals<K, V>(Map<K, List<V>> a, Map<K, List<V>> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    final other = b[e.key];
    if (other == null || !listEquals(e.value, other)) return false;
  }
  return true;
}
