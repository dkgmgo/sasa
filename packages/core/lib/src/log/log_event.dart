import 'dart:convert';
import 'dart:math';

import '../json.dart';
import '../time_zones.dart';

/// Random (version 4) UUID, e.g. `0b7f0c8e-2a51-4c2a-9b55-1a3c1b1b2c3d`.
///
/// Takes the [Random] so tests are reproducible; production code passes
/// `Random.secure()`.
String uuidV4(Random random) {
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final _deviceId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');

/// True when [id] is safe as a folder name on every platform and sync tool:
/// ASCII letters, digits, `.`, `_`, `-`, not starting with a dot, ≤ 64 chars.
bool isValidDeviceId(String id) => _deviceId.hasMatch(id);

/// New device id such as `linux-3f2a9c1b`. Generated once per installation
/// and stored outside the synced folder.
String generateDeviceId(String prefix, Random random) {
  final suffix = List.generate(
    4,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final id = '$prefix-$suffix';
  if (!isValidDeviceId(id)) {
    throw ArgumentError.value(prefix, 'prefix', 'not usable in a device id');
  }
  return id;
}

/// Name of the monthly log file an event at [ts] goes to:
/// `log-YYYY-MM.jsonl`, by UTC month.
String logFileName(DateTime ts) {
  final u = ts.toUtc();
  return 'log-${u.year.toString().padLeft(4, '0')}-'
      '${u.month.toString().padLeft(2, '0')}.jsonl';
}

/// One line of a device log: the envelope around an event's data.
///
/// `{id: uuid, ts: ISO-8601 UTC, device, type, v: schemaVersion, data: {…}}`
///
/// Ordering ([compareTo]) is by [ts], then [device], then [id], so every
/// device folds the merged logs in the same order.
final class LogEvent implements Comparable<LogEvent> {
  LogEvent({
    required this.id,
    required DateTime ts,
    required this.device,
    required this.type,
    required this.v,
    required Map<String, Object?> data,
  }) : ts = utcInstant(ts),
       data = Map.unmodifiable(data);

  /// Parses one log line. Throws [FormatException] for anything that is not
  /// a complete, valid envelope. Unknown envelope keys are ignored; `data`
  /// may be omitted.
  factory LogEvent.fromLine(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (e) {
      throw FormatException('Not JSON: ${e.message}');
    }
    final json = asJson(decoded, 'event');
    final id = json.req<String>('id');
    if (id.isEmpty) throw const FormatException('Empty event id');
    final device = json.req<String>('device');
    if (!isValidDeviceId(device)) {
      throw FormatException('Invalid device id "$device"');
    }
    final type = json.req<String>('type');
    if (type.isEmpty) throw const FormatException('Empty event type');
    final v = json.req<int>('v');
    if (v < 1) throw FormatException('Invalid schema version $v');
    return LogEvent(
      id: id,
      ts: json.reqInstant('ts'),
      device: device,
      type: type,
      v: v,
      data: json.optObject('data') ?? const {},
    );
  }

  final String id;

  /// When the event happened, UTC.
  final DateTime ts;

  /// Id of the device that wrote it (and owns the file it is in).
  final String device;

  /// Event type, e.g. `session.completed`.
  final String type;

  /// Schema version of [data].
  final int v;
  final Map<String, Object?> data;

  Json toJson() => {
    'id': id,
    'ts': instantToJson(ts),
    'device': device,
    'type': type,
    'v': v,
    'data': data,
  };

  /// One line of JSON with no newline (JSON escapes newlines in strings).
  String toLine() => jsonEncode(toJson());

  @override
  int compareTo(LogEvent other) {
    final byTs = ts.compareTo(other.ts);
    if (byTs != 0) return byTs;
    final byDevice = device.compareTo(other.device);
    if (byDevice != 0) return byDevice;
    return id.compareTo(other.id);
  }

  @override
  bool operator ==(Object other) =>
      other is LogEvent &&
      other.id == id &&
      other.ts == ts &&
      other.device == device &&
      other.type == type &&
      other.v == v &&
      jsonEncode(other.data) == jsonEncode(data);

  @override
  int get hashCode => Object.hash(id, ts, device, type, v);

  @override
  String toString() => 'LogEvent($type @ $ts from $device, $id)';
}
