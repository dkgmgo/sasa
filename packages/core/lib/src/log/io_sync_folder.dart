import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'sync_folder.dart';

/// [SyncFolder] on a plain directory (Linux, the CLI, tests).
final class IoSyncFolder implements SyncFolder {
  IoSyncFolder(this.rootPath);

  /// Absolute path of the synced folder.
  final String rootPath;

  static final _tmpRandom = Random();

  String _abs(String path, {bool allowRoot = false}) {
    final segments = checkPath(path, allowRoot: allowRoot);
    return [rootPath, ...segments].join(Platform.pathSeparator);
  }

  @override
  Future<List<FolderEntry>> list(String dir) async {
    final d = Directory(_abs(dir, allowRoot: true));
    if (!d.existsSync()) return const [];
    final out = <FolderEntry>[];
    await for (final e in d.list(followLinks: false)) {
      final name = e.path.substring(
        e.path.lastIndexOf(Platform.pathSeparator) + 1,
      );
      if (e is Directory) {
        out.add(FolderEntry(name, isDirectory: true));
      } else if (e is File) {
        out.add(FolderEntry(name, isDirectory: false));
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  @override
  Future<String?> read(String path) async {
    final f = File(_abs(path));
    try {
      return await f.readAsString();
    } on PathNotFoundException {
      return null;
    }
  }

  /// Appends still running in this isolate, by absolute path.
  static final Map<String, Future<void>> _appending = {};

  @override
  Future<void> append(String path, String text) {
    final abs = _abs(path);
    final previous = _appending[abs] ?? Future.value();
    final done = previous.then((_) => _appendLocked(abs, text));
    final tail = done.then((_) {}, onError: (_) {});
    _appending[abs] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_appending[abs], tail)) _appending.remove(abs);
      }),
    );
    return done;
  }

  // dart:io's FileMode.append seeks to the end once at open time; it does
  // not use O_APPEND. So writers are serialised: in this isolate by
  // [_appending], across processes (the app and the CLI) by an exclusive
  // lock, and the position is moved to the end only once the lock is held.
  static Future<void> _appendLocked(String abs, String text) async {
    final f = File(abs);
    await f.parent.create(recursive: true);
    final raf = await f.open(mode: FileMode.append);
    try {
      await raf.lock(FileLock.blockingExclusive);
      await raf.setPosition(await raf.length());
      await raf.writeFrom(utf8.encode(text));
      await raf.flush();
    } finally {
      await raf.close();
    }
  }

  @override
  Future<void> write(String path, String text) async {
    final f = File(_abs(path));
    await f.parent.create(recursive: true);
    final name = path.substring(path.lastIndexOf('/') + 1);
    final suffix = _tmpRandom.nextInt(1 << 32).toRadixString(16);
    final tmp = File(
      '${f.parent.path}${Platform.pathSeparator}'
      '.$name.sasa-tmp-$suffix',
    );
    try {
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      if (tmp.existsSync()) tmp.deleteSync();
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      await File(_abs(path)).delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}
