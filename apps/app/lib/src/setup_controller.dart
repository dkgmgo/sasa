import 'package:flutter/foundation.dart';
import 'package:saf_folder/saf_folder.dart';
import 'package:sasa_core/sasa_core.dart';

import 'data_controller.dart';
import 'device_settings.dart';
import 'folder_access.dart';
import 'secret_store.dart';
import 'source_controller.dart';

/// Tries an account against the server. Returns a short success message
/// (e.g. "Found 2 calendars"); throws [ConnectionFailed] on failure. Never
/// includes the password in either.
typedef CalDavTester = Future<String> Function(CalDavAccount account);

/// A failed connection test, with a message for the user.
final class ConnectionFailed implements Exception {
  const ConnectionFailed(this.message);
  final String message;

  @override
  String toString() => message;
}

/// State and rules of the setup screen: choose the synced folder, choose the
/// calendar source, enter the CalDAV account.
final class SetupController extends ChangeNotifier {
  SetupController({
    required this.platform,
    required this.settings,
    required this.secrets,
    required this.access,
    required this.data,
    required this.sources,
    this.testCalDav,
  });

  final SourcePlatform platform;
  final DeviceSettings settings;
  final SecretStore secrets;
  final FolderAccess access;
  final DataController data;
  final SourceController sources;
  final CalDavTester? testCalDav;

  FolderLocation? _savedFolder;
  FolderLocation? _folder;
  int? _existingDevices;
  bool _useDavx = true;
  String _url = '';
  String _username = '';
  String _password = '';
  CalDavAccount? _saved;
  bool _busy = false;
  String? _error;
  String? _connection;
  bool? _connectionOk;

  bool get isAndroid => platform == SourcePlatform.android;
  FolderLocation? get folder => _folder;

  /// Device folders already in the picked folder's `Sasa/devices/`.
  int? get existingDevices => _existingDevices;

  /// Android only: read calendars and tasks synced by DAVx⁵.
  bool get useDavx => isAndroid && _useDavx;
  String get url => _url;
  String get username => _username;

  /// True when a password is stored; an empty field then keeps it.
  bool get hasSavedPassword => _saved != null;
  bool get busy => _busy;
  String? get error => _error;
  String? get connectionMessage => _connection;
  bool? get connectionOk => _connectionOk;

  /// CalDAV is the source unless DAVx⁵ is used. With DAVx⁵ an account is
  /// optional (a fallback for tasks when Tasks.org is missing).
  bool get calDavRequired => !useDavx;

  bool get _anyAccountField =>
      _url.trim().isNotEmpty ||
      _username.trim().isNotEmpty ||
      _password.isNotEmpty;

  /// Fills the form from what this device already has.
  Future<void> load() async {
    _savedFolder = await settings.syncFolder();
    _folder = _savedFolder;
    _useDavx = !await settings.forceCalDav();
    _saved = await secrets.calDavAccount();
    if (_saved != null) {
      _url = _saved!.url.toString();
      _username = _saved!.username;
    }
    if (_folder != null) await _countDevices();
    notifyListeners();
  }

  void setUseDavx(bool value) {
    _useDavx = value;
    notifyListeners();
  }

  void setUrl(String v) => _edit(() => _url = v);
  void setUsername(String v) => _edit(() => _username = v);
  void setPassword(String v) => _edit(() => _password = v);

  void _edit(void Function() change) {
    change();
    _connection = null;
    _connectionOk = null;
    notifyListeners();
  }

  /// Shows the folder picker.
  Future<void> pickFolder() => _run(() async {
    final picked = await access.pick(current: _folder);
    if (picked == null) return;
    _folder = picked;
    await _countDevices();
  });

  Future<void> _countDevices() async {
    try {
      final entries = await access.open(_folder!).list('Sasa/devices');
      _existingDevices = entries
          .where((e) => e.isDirectory && isValidDeviceId(e.name))
          .length;
    } on Object {
      _existingDevices = null;
    }
  }

  String? get urlError {
    if (!calDavRequired && !_anyAccountField) return null;
    return CalDavAccount.checkUrl(_url);
  }

  /// Shown under the URL when the password would travel unencrypted.
  bool get urlInsecure {
    if (urlError != null) return false;
    return CalDavAccount.isInsecure(Uri.parse(_url.trim()));
  }

  String? get usernameError {
    if (!calDavRequired && !_anyAccountField) return null;
    return _username.trim().isEmpty ? 'Enter your user name' : null;
  }

  String? get passwordError {
    if (!calDavRequired && !_anyAccountField) return null;
    if (_password.isEmpty && !hasSavedPassword) return 'Enter your password';
    return null;
  }

  /// The account from the form; an empty password keeps the saved one.
  CalDavAccount? get _account {
    if (urlError != null || usernameError != null || passwordError != null) {
      return null;
    }
    if (!_anyAccountField) return null;
    return CalDavAccount(
      url: Uri.parse(_url.trim()),
      username: _username.trim(),
      password: _password.isEmpty ? _saved!.password : _password,
    );
  }

  bool get canTestConnection =>
      testCalDav != null && _account != null && !_busy;

  /// Why [finish] is not possible yet, or null.
  String? get blocker {
    if (_folder == null) return 'Choose the synced folder first.';
    if (urlError != null || usernameError != null || passwordError != null) {
      return 'Complete the CalDAV account.';
    }
    return null;
  }

  Future<void> testConnection() => _run(() async {
    final account = _account;
    final tester = testCalDav;
    if (account == null || tester == null) return;
    try {
      _connection = await tester(account);
      _connectionOk = true;
    } on ConnectionFailed catch (e) {
      _connection = e.message;
      _connectionOk = false;
    }
  });

  /// Saves everything and opens the folder. Returns true on success.
  Future<bool> finish() async {
    if (blocker != null) return false;
    var ok = false;
    await _run(() async {
      final folder = _folder!;
      if (!await data.open(folder)) {
        _error = data.accessLost
            ? 'Sasa cannot open this folder any more. Choose it again.'
            : 'Sasa cannot open this folder.';
        return;
      }
      final old = _savedFolder;
      if (old != null && old != folder) {
        try {
          await access.forget(old);
        } on SafFolderException {
          // Already gone.
        }
      }
      await settings.setSyncFolder(folder);
      _savedFolder = folder;
      if (isAndroid) await settings.setForceCalDav(!_useDavx);
      final account = _account;
      if (account != null) {
        await secrets.setCalDavAccount(account);
        _saved = account;
        _password = '';
      }
      await settings.setSetupDone(true);
      await sources.refresh();
      ok = true;
    });
    return ok;
  }

  Future<void> _run(Future<void> Function() work) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await work();
    } on SafAccessLost {
      _error = 'Access to the folder was lost. Choose it again.';
    } on SafFolderException catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
