import 'dart:convert';
import 'dart:io';

import 'json.dart';

/// What this machine knows about itself: never synced.
final class DeviceInfo {
  const DeviceInfo({this.deviceId, this.syncFolder});

  /// This device's folder name under `Sasa/devices/`.
  final String? deviceId;

  /// Absolute path of the synced folder (the one that contains `Sasa/`).
  final String? syncFolder;

  DeviceInfo copyWith({String? deviceId, String? syncFolder}) => DeviceInfo(
    deviceId: deviceId ?? this.deviceId,
    syncFolder: syncFolder ?? this.syncFolder,
  );

  Json toJson() => {'deviceId': ?deviceId, 'syncFolder': ?syncFolder};
}

/// `device.json` in the user's config dir, shared by the Linux app and the
/// CLI so both write as the same device to the same folder. Holds no
/// secrets.
final class DeviceFile {
  DeviceFile(this.path);

  /// `$XDG_CONFIG_HOME/sasa/device.json`, else `~/.config/sasa/device.json`;
  /// null when neither variable is set.
  static String? defaultPath(Map<String, String> env) {
    final xdg = env['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) return '$xdg/sasa/device.json';
    final home = env['HOME'];
    if (home == null || home.isEmpty) return null;
    return '$home/.config/sasa/device.json';
  }

  final String path;

  /// Empty info when the file does not exist; [FormatException] if corrupt.
  Future<DeviceInfo> read() async {
    final String text;
    try {
      text = await File(path).readAsString();
    } on PathNotFoundException {
      return const DeviceInfo();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('$path is not valid JSON: ${e.message}');
    }
    final j = asJson(decoded, path);
    return DeviceInfo(
      deviceId: j.opt<String>('deviceId'),
      syncFolder: j.opt<String>('syncFolder'),
    );
  }

  Future<void> write(DeviceInfo info) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(info.toJson())}\n',
      flush: true,
    );
    await tmp.rename(path);
  }
}
