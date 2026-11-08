import 'package:flutter/services.dart';
import 'package:sasa_core/sasa_core.dart';

/// A folder the user picked, with persisted access.
final class PickedTree {
  const PickedTree({required this.uri, required this.name});

  /// `content://…/tree/…` URI; store it to reopen the folder later.
  final String uri;

  /// Display name of the folder, e.g. `Sync`.
  final String name;

  @override
  String toString() => 'PickedTree($name)';
}

/// Access to the folder is gone: the user revoked it in system settings, or
/// the folder was deleted. The app should ask to pick it again.
final class SafAccessLost implements Exception {
  const SafAccessLost(this.message);
  final String message;

  @override
  String toString() => 'SafAccessLost: $message';
}

/// Any other failure from the platform side.
final class SafFolderException implements Exception {
  const SafFolderException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'SafFolderException($code): $message';
}

/// Operations on Storage Access Framework trees. Paths are relative to the
/// tree and use core's rules (see `SyncFolder`).
abstract interface class SafFolderApi {
  /// Shows the system folder picker and persists read+write access. Null
  /// when the user cancels. Needs the app in the foreground.
  Future<PickedTree?> pickTree({String? initialUri});

  /// True while [treeUri] is still accessible.
  Future<bool> hasAccess(String treeUri);

  /// Current display name; throws [SafAccessLost].
  Future<PickedTree> describe(String treeUri);

  /// Gives up the persisted access (when the user picks another folder).
  Future<void> release(String treeUri);

  Future<List<FolderEntry>> list(String treeUri, String path);
  Future<String?> read(String treeUri, String path);
  Future<void> append(String treeUri, String path, String text);
  Future<void> write(String treeUri, String path, String text);
  Future<void> delete(String treeUri, String path);
}

/// [SafFolderApi] over the plugin's method channel. Works in the UI and in a
/// WorkManager background engine (except [pickTree]).
final class SafFolder implements SafFolderApi {
  SafFolder({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'fr.dkgmgo.saf_folder';

  final MethodChannel _channel;

  Future<T?> _call<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      final message = e.message ?? method;
      switch (e.code) {
        case 'access_lost':
          throw SafAccessLost(message);
        case 'invalid_path':
          throw ArgumentError(message);
        default:
          throw SafFolderException(e.code, message);
      }
    } on MissingPluginException {
      throw const SafFolderException(
        'unavailable',
        'The folder picker is only available on Android',
      );
    }
  }

  static PickedTree _tree(Map<Object?, Object?> m) =>
      PickedTree(uri: m['uri']! as String, name: (m['name'] as String?) ?? '');

  @override
  Future<PickedTree?> pickTree({String? initialUri}) async {
    final m = await _call<Map<Object?, Object?>>('pickTree', {
      'initialUri': ?initialUri,
    });
    return m == null ? null : _tree(m);
  }

  @override
  Future<bool> hasAccess(String treeUri) async =>
      await _call<bool>('hasAccess', {'treeUri': treeUri}) ?? false;

  @override
  Future<PickedTree> describe(String treeUri) async => _tree(
    (await _call<Map<Object?, Object?>>('describe', {'treeUri': treeUri}))!,
  );

  @override
  Future<void> release(String treeUri) =>
      _call<void>('release', {'treeUri': treeUri});

  @override
  Future<List<FolderEntry>> list(String treeUri, String path) async {
    final rows =
        await _call<List<Object?>>('list', {
          'treeUri': treeUri,
          'path': path,
        }) ??
        const [];
    return [
      for (final r in rows.cast<Map<Object?, Object?>>())
        FolderEntry(
          r['name']! as String,
          isDirectory: r['isDirectory']! as bool,
        ),
    ];
  }

  @override
  Future<String?> read(String treeUri, String path) =>
      _call<String>('read', {'treeUri': treeUri, 'path': path});

  @override
  Future<void> append(String treeUri, String path, String text) =>
      _call<void>('append', {'treeUri': treeUri, 'path': path, 'text': text});

  @override
  Future<void> write(String treeUri, String path, String text) =>
      _call<void>('write', {'treeUri': treeUri, 'path': path, 'text': text});

  @override
  Future<void> delete(String treeUri, String path) =>
      _call<void>('delete', {'treeUri': treeUri, 'path': path});
}
