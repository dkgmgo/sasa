import 'dart:convert';
import 'dart:math';

import '../clock.dart';
import '../config/app_config.dart';
import '../json.dart';
import 'event_log.dart';
import 'sync_folder.dart';

/// A copy of `config.json` made by the sync tool when two devices changed it
/// at the same time.
final class ConfigConflict {
  const ConfigConflict(this.name, this.updatedAt);

  /// File name inside the app folder.
  final String name;

  /// Its `updatedAt`, or null when the copy cannot be read.
  final DateTime? updatedAt;

  @override
  String toString() => 'ConfigConflict($name, $updatedAt)';
}

/// Syncthing: `config.sync-conflict-<date>-<time>-<device>.json`.
/// Nextcloud desktop: `config (conflicted copy <date> <time>).json`.
/// Nextcloud Android and others: `config_conflict-<…>.json`.
final _conflictName = RegExp(r'^config[ ._(].*conflict.*\.json$');

/// The app's folder inside the synced folder:
///
/// ```
/// <synced folder>/Sasa/
/// ├── config.json        categories, rules, targets (no secrets)
/// ├── devices/<id>/…     per-device event logs
/// └── reports/…          generated weekly reports
/// ```
final class SasaFolder {
  SasaFolder(this.folder, {this.root = 'Sasa'}) {
    checkPath(root);
  }

  final SyncFolder folder;
  final String root;

  String get configPath => '$root/config.json';

  /// The event log of this device.
  EventLog eventLog({
    required String deviceId,
    required Clock clock,
    Random? random,
  }) => EventLog(
    folder: folder,
    deviceId: deviceId,
    clock: clock,
    random: random,
    root: root,
  );

  /// Reads `config.json`; null when there is none yet.
  ///
  /// Throws [FormatException] when it is corrupt and
  /// [UnsupportedConfigVersion] when it is from a newer app.
  Future<AppConfig?> loadConfig() async {
    final text = await folder.read(configPath);
    return text == null ? null : _parse(text);
  }

  /// Reads `config.json`, writing the defaults first when there is none.
  /// A corrupt file is reported, never overwritten.
  Future<AppConfig> loadOrCreateConfig(Clock clock) async {
    final existing = await loadConfig();
    if (existing != null) return existing;
    final fresh = AppConfig.defaults(clock: clock);
    await saveConfig(fresh);
    return fresh;
  }

  /// Replaces `config.json`. Callers bump [AppConfig.updatedAt] on every
  /// change: across devices, the newest `updatedAt` wins.
  Future<void> saveConfig(AppConfig config) => folder.write(
    configPath,
    '${const JsonEncoder.withIndent('  ').convert(config.toJson())}\n',
  );

  /// Conflict copies of `config.json` left by the sync tool, for a banner.
  Future<List<ConfigConflict>> configConflicts() async {
    final out = <ConfigConflict>[];
    for (final e in await folder.list(root)) {
      if (e.isDirectory || !_conflictName.hasMatch(e.name)) continue;
      DateTime? updatedAt;
      try {
        final text = await folder.read('$root/${e.name}');
        if (text != null) updatedAt = _parse(text).updatedAt;
      } on Object catch (err) {
        if (err is! FormatException && err is! UnsupportedConfigVersion) {
          rethrow;
        }
      }
      out.add(ConfigConflict(e.name, updatedAt));
    }
    return out;
  }

  /// Resolves conflicts by last-writer-wins: keeps the readable version
  /// (main file or copy) with the newest `updatedAt` as `config.json` and
  /// deletes the readable copies. Unreadable copies are left in place.
  ///
  /// Returns the kept configuration. Throws [StateError] when no version is
  /// readable.
  Future<AppConfig> keepNewestConfig() async {
    AppConfig? best;
    try {
      best = await loadConfig();
    } on FormatException {
      best = null;
    }
    final readable = <String>[];
    for (final c in await configConflicts()) {
      if (c.updatedAt == null) continue;
      readable.add(c.name);
      final copy = _parse((await folder.read('$root/${c.name}'))!);
      if (best == null || copy.updatedAt.isAfter(best.updatedAt)) best = copy;
    }
    if (best == null) throw StateError('No readable config.json');
    await saveConfig(best);
    for (final name in readable) {
      await folder.delete('$root/$name');
    }
    return best;
  }

  AppConfig _parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('config.json is not valid JSON: ${e.message}');
    }
    return AppConfig.fromJson(asJson(decoded, 'config.json'));
  }
}
