import 'package:sasa_core/sasa_core.dart';

import 'saf_folder.dart';

/// Core's [SyncFolder] inside one picked SAF tree.
///
/// Paths are checked on the Dart side first, so a bad path never reaches the
/// platform. Throws [SafAccessLost] when the grant is gone.
final class SafSyncFolder implements SyncFolder {
  SafSyncFolder(this.api, this.treeUri);

  final SafFolderApi api;
  final String treeUri;

  @override
  Future<List<FolderEntry>> list(String dir) async {
    checkPath(dir, allowRoot: true);
    return await api.list(treeUri, dir);
  }

  @override
  Future<String?> read(String path) async {
    checkPath(path);
    return await api.read(treeUri, path);
  }

  @override
  Future<void> append(String path, String text) async {
    checkPath(path);
    await api.append(treeUri, path, text);
  }

  @override
  Future<void> write(String path, String text) async {
    checkPath(path);
    await api.write(treeUri, path, text);
  }

  @override
  Future<void> delete(String path) async {
    checkPath(path);
    await api.delete(treeUri, path);
  }
}
