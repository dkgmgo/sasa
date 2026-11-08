import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:saf_folder/saf_folder.dart';
import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';

/// How a synced folder is addressed on this platform.
enum FolderKind {
  /// A plain directory path (Linux).
  path,

  /// A Storage Access Framework tree URI with persisted access (Android).
  safTree,
}

/// The synced folder this device uses. Stored in device settings, never in
/// the synced folder itself.
final class FolderLocation {
  const FolderLocation({
    required this.kind,
    required this.ref,
    required this.name,
  });

  factory FolderLocation.fromJson(Map<String, Object?> j) => FolderLocation(
    kind: FolderKind.values.byName(j['kind']! as String),
    ref: j['ref']! as String,
    name: j['name']! as String,
  );

  final FolderKind kind;

  /// The path or the tree URI.
  final String ref;

  /// Short name for the UI (e.g. `Sync`).
  final String name;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'ref': ref,
    'name': name,
  };

  @override
  bool operator ==(Object other) =>
      other is FolderLocation &&
      other.kind == kind &&
      other.ref == ref &&
      other.name == name;

  @override
  int get hashCode => Object.hash(kind, ref, name);

  @override
  String toString() => 'FolderLocation($name, $ref)';
}

/// Picking and opening the synced folder, per platform.
abstract interface class FolderAccess {
  /// Shows the platform's folder picker; null when cancelled.
  Future<FolderLocation?> pick({FolderLocation? current});

  /// False when the folder is gone or access was revoked.
  Future<bool> isAccessible(FolderLocation location);

  SyncFolder open(FolderLocation location);

  /// Gives up access to a folder that is no longer used.
  Future<void> forget(FolderLocation location);
}

/// Android: Storage Access Framework tree with persisted access.
final class SafFolderAccess implements FolderAccess {
  SafFolderAccess(this.api);

  final SafFolderApi api;

  @override
  Future<FolderLocation?> pick({FolderLocation? current}) async {
    final tree = await api.pickTree(
      initialUri: current?.kind == FolderKind.safTree ? current!.ref : null,
    );
    if (tree == null) return null;
    return FolderLocation(
      kind: FolderKind.safTree,
      ref: tree.uri,
      name: tree.name,
    );
  }

  @override
  Future<bool> isAccessible(FolderLocation location) =>
      api.hasAccess(location.ref);

  @override
  SyncFolder open(FolderLocation location) => SafSyncFolder(api, location.ref);

  @override
  Future<void> forget(FolderLocation location) => api.release(location.ref);
}

/// Linux (and other desktops): a plain directory chosen with the system
/// file dialog.
final class PathFolderAccess implements FolderAccess {
  PathFolderAccess({Future<String?> Function(String? initial)? pickDirectory})
    : _pickDirectory =
          pickDirectory ??
          ((initial) => fs.getDirectoryPath(
            initialDirectory: initial,
            confirmButtonText: 'Use this folder',
          ));

  final Future<String?> Function(String? initial) _pickDirectory;

  @override
  Future<FolderLocation?> pick({FolderLocation? current}) async {
    final path = await _pickDirectory(
      current?.kind == FolderKind.path ? current!.ref : null,
    );
    return path == null ? null : locationOf(path);
  }

  /// [FolderLocation] for a directory [path], named after its last part.
  static FolderLocation locationOf(String path) => FolderLocation(
    kind: FolderKind.path,
    ref: path,
    name: path
        .split(Platform.pathSeparator)
        .lastWhere((s) => s.isNotEmpty, orElse: () => path),
  );

  @override
  Future<bool> isAccessible(FolderLocation location) async =>
      Directory(location.ref).existsSync();

  @override
  SyncFolder open(FolderLocation location) => IoSyncFolder(location.ref);

  @override
  Future<void> forget(FolderLocation location) async {}
}
