import 'package:flutter/foundation.dart';
import 'package:saf_folder/saf_folder.dart';
import 'package:sasa_core/sasa_core.dart';

import 'device_settings.dart';
import 'folder_access.dart';

/// The app data in the synced folder: `config.json` and the event logs.
///
/// Opens the folder from [settings], loads everything, and exposes the
/// result (and any problem) for the UI. Logic stays in core.
final class DataController extends ChangeNotifier {
  DataController({
    required this.settings,
    required this.access,
    required this.clock,
  });

  final DeviceSettings settings;
  final FolderAccess access;
  final Clock clock;

  FolderLocation? _location;
  SasaFolder? _folder;
  EventLog? _log;
  AppConfig? _config;
  LogSnapshot? _snapshot;
  List<ConfigConflict> _conflicts = const [];
  String? _error;
  bool _accessLost = false;
  bool _busy = false;

  FolderLocation? get location => _location;
  AppConfig? get config => _config;
  LogSnapshot? get snapshot => _snapshot;
  List<ConfigConflict> get conflicts => _conflicts;

  /// This device's log; null until a folder is open.
  EventLog? get log => _log;

  /// A problem reading the folder (e.g. a corrupt `config.json`).
  String? get error => _error;

  /// The folder is gone or access was revoked: it must be chosen again.
  bool get accessLost => _accessLost;
  bool get busy => _busy;
  bool get isOpen => _folder != null && !_accessLost;

  /// Opens the folder saved in [settings]. Returns false when there is none
  /// or it cannot be reached.
  Future<bool> openSaved() async {
    final saved = await settings.syncFolder();
    if (saved == null) return false;
    return open(saved);
  }

  /// Opens [location], creating `Sasa/config.json` with defaults if it has
  /// none, and loads the logs.
  Future<bool> open(FolderLocation location) => _run(false, () async {
    _location = location;
    _accessLost = !await access.isAccessible(location);
    if (_accessLost) {
      _folder = null;
      _log = null;
      return false;
    }
    final folder = SasaFolder(access.open(location));
    _folder = folder;
    _log = folder.eventLog(deviceId: await settings.deviceId(), clock: clock);
    await _load();
    return true;
  });

  /// Reloads config, logs and conflicts.
  Future<void> reload() => _run(null, () async {
    if (_folder != null) await _load();
  });

  /// Resolves `config.json` conflicts: the newest version wins.
  Future<void> keepNewestConfig() => _run(null, () async {
    final f = _folder;
    if (f == null) return;
    _config = await f.keepNewestConfig();
    _conflicts = await f.configConflicts();
  });

  /// Applies [edit] to the newest `config.json` and saves it.
  ///
  /// The file is read again first, so a change synced from another device
  /// since the last load is kept. Returns null on success, else a message
  /// for the user (the edit's target is gone, the file is unreadable, the
  /// folder is lost).
  Future<String?> updateConfig(ConfigEdit edit) =>
      _run('Sasa can no longer open the synced folder.', () async {
        final f = _folder;
        if (f == null) return 'No synced folder is open.';
        try {
          final base = await f.loadConfig() ?? _config;
          if (base == null) return 'config.json cannot be read.';
          final next = applyConfigEdit(base, edit, clock);
          await f.saveConfig(next);
          _config = next;
          _error = null;
          return null;
        } on ConfigEditConflict {
          await _load();
          return 'This was changed on another device. Showing the latest '
              'version; try again.';
        } on FormatException catch (e) {
          return 'config.json cannot be read (${e.message}).';
        } on UnsupportedConfigVersion catch (e) {
          return '$e';
        }
      });

  Future<void> _load() async {
    final f = _folder!;
    _error = null;
    try {
      _config = await f.loadOrCreateConfig(clock);
    } on FormatException catch (e) {
      _config = null;
      _error = 'config.json cannot be read (${e.message}). Fix or delete it.';
    } on UnsupportedConfigVersion catch (e) {
      _config = null;
      _error = '$e';
    }
    _snapshot = await _log!.load();
    _conflicts = await f.configConflicts();
  }

  /// Runs [work]; a revoked folder grant gives [onAccessLost] instead.
  Future<T> _run<T>(T onAccessLost, Future<T> Function() work) async {
    _busy = true;
    notifyListeners();
    try {
      return await work();
    } on SafAccessLost {
      _accessLost = true;
      _folder = null;
      _log = null;
      return onAccessLost;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
