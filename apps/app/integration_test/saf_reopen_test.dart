// On-device check of the Storage Access Framework folder plugin, phase 2.
// Run after saf_pick_test.dart, in a new app process:
//
//   flutter test integration_test/saf_reopen_test.dart -d <device> --no-uninstall
//
// Checks that the folder grant survived the restart, then deletes the test
// files and releases the grant.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saf_folder/saf_folder.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'saf_pick_test.dart' show rootKey, treeKey;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SAF folder: access persists, then clean up', (_) async {
    final prefs = SharedPreferencesAsync();
    final tree = await prefs.getString(treeKey);
    final root = await prefs.getString(rootKey);
    expect(tree, isNotNull, reason: 'run saf_pick_test.dart first');
    final api = SafFolder();
    final f = SafSyncFolder(api, tree!);

    expect(await api.hasAccess(tree), isTrue);
    expect(await f.read('$root/marker.txt'), 'phase 1 ok');
    final snap = await EventLog(
      folder: f,
      deviceId: 'android-test',
      clock: FakeClock(DateTime.utc(2026, 11, 8)),
      root: root!,
    ).load();
    expect(snap.events, hasLength(61));

    // Clean up every file phase 1 wrote (empty folders stay).
    Future<void> wipe(String dir) async {
      for (final e in await f.list(dir)) {
        final path = '$dir/${e.name}';
        if (e.isDirectory) {
          await wipe(path);
        } else {
          await f.delete(path);
        }
      }
    }

    await wipe(root);
    expect(await f.read('$root/marker.txt'), isNull);

    await api.release(tree);
    expect(await api.hasAccess(tree), isFalse);
    await expectLater(
      f.read('$root/marker.txt'),
      throwsA(isA<SafAccessLost>()),
    );
    await prefs.remove(treeKey);
    await prefs.remove(rootKey);
    debugPrint('>>> Phase 2 done: grant persisted, files removed, released.');
  });
}
