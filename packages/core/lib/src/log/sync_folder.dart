/// The folder that a sync tool (Syncthing, Nextcloud) keeps in step between
/// devices, seen through a small file API so the same log code runs on a
/// plain path (Linux, CLI), Android's Storage Access Framework and memory.
library;

/// One child of a folder.
final class FolderEntry {
  const FolderEntry(this.name, {required this.isDirectory});

  final String name;
  final bool isDirectory;

  @override
  bool operator ==(Object other) =>
      other is FolderEntry &&
      other.name == name &&
      other.isDirectory == isDirectory;

  @override
  int get hashCode => Object.hash(name, isDirectory);

  @override
  String toString() => isDirectory ? '$name/' : name;
}

/// File access relative to the root of the synced folder.
///
/// Paths use `/`, are relative, and never contain empty, `.` or `..`
/// segments; anything else is an [ArgumentError]. Missing parents are created
/// on write.
abstract interface class SyncFolder {
  /// Children of [dir] (`''` is the root), sorted by name. Empty when [dir]
  /// does not exist.
  Future<List<FolderEntry>> list(String dir);

  /// Whole file as UTF-8 text, or null when it does not exist.
  Future<String?> read(String path);

  /// Appends [text] in one write, creating the file if needed.
  ///
  /// Implementations open the file in append mode, so writers in other
  /// processes of the same device cannot interleave inside one call.
  Future<void> append(String path, String text);

  /// Replaces the file with [text]. Implementations write a temporary file
  /// and rename it where the platform allows, so readers never see half a
  /// file.
  Future<void> write(String path, String text);

  /// Removes the file; does nothing if it does not exist.
  Future<void> delete(String path);
}

/// Splits [path] into segments, rejecting anything that could leave the
/// folder. [allowRoot] accepts `''` (for listing the root).
List<String> checkPath(String path, {bool allowRoot = false}) {
  if (path.isEmpty) {
    if (allowRoot) return const [];
    throw ArgumentError.value(path, 'path', 'must not be empty');
  }
  final segments = path.split('/');
  for (final s in segments) {
    if (s.isEmpty || s == '.' || s == '..' || s.contains(r'\')) {
      throw ArgumentError.value(path, 'path', 'must be a plain relative path');
    }
  }
  return segments;
}

/// In-memory [SyncFolder] for tests. Directories exist implicitly when they
/// contain a file.
final class MemorySyncFolder implements SyncFolder {
  final Map<String, String> _files = {};

  /// Snapshot of every file, by path.
  Map<String, String> get files => Map.unmodifiable(_files);

  @override
  Future<List<FolderEntry>> list(String dir) async {
    final prefix = checkPath(dir, allowRoot: true).isEmpty ? '' : '$dir/';
    final entries = <String, bool>{};
    for (final path in _files.keys) {
      if (!path.startsWith(prefix)) continue;
      final rest = path.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        entries[rest] = false;
      } else {
        entries[rest.substring(0, slash)] = true;
      }
    }
    final names = entries.keys.toList()..sort();
    return [for (final n in names) FolderEntry(n, isDirectory: entries[n]!)];
  }

  @override
  Future<String?> read(String path) async {
    checkPath(path);
    return _files[path];
  }

  @override
  Future<void> append(String path, String text) async {
    checkPath(path);
    // Yield first (a microtask, not a timer, so widget tests settle), so
    // concurrent callers really interleave.
    await Future<void>.value();
    _files[path] = (_files[path] ?? '') + text;
  }

  @override
  Future<void> write(String path, String text) async {
    checkPath(path);
    await Future<void>.value();
    _files[path] = text;
  }

  @override
  Future<void> delete(String path) async {
    checkPath(path);
    _files.remove(path);
  }

  /// Appends [text] as a crashed writer would leave it (e.g. half a line),
  /// synchronously.
  void corruptAppend(String path, String text) {
    _files[path] = (_files[path] ?? '') + text;
  }
}
