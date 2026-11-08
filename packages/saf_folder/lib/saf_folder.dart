/// Files in a folder picked with Android's Storage Access Framework.
///
/// - [SafFolder]: method-channel API (`fr.dkgmgo.saf_folder`): pick a tree
///   with persisted access, then list/read/append/write/delete by relative
///   path.
/// - [SafSyncFolder]: core's `SyncFolder` on top of it.
library;

export 'src/saf_folder.dart';
export 'src/saf_sync_folder.dart';
