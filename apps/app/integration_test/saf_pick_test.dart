// On-device check of the Storage Access Framework folder plugin, phase 1.
//
//   flutter test integration_test/saf_pick_test.dart -d <device> --no-uninstall
//
// --no-uninstall keeps the folder grant for phase 2. The test opens the
// system folder picker: choose an EMPTY THROWAWAY folder. Everything is
// written under a unique `sasa-device-test-<n>/` subfolder; files are deleted
// again in phase 2, which also checks that access survived a restart.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saf_folder/saf_folder.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared with phase 2.
const treeKey = 'integrationTest.saf.tree';
const rootKey = 'integrationTest.saf.root';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SAF folder: pick, write, append, list, event log', (_) async {
    final api = SafFolder();
    debugPrint('>>> Pick an EMPTY throwaway folder in the picker now.');
    final picked = await api.pickTree().timeout(const Duration(minutes: 5));
    expect(picked, isNotNull, reason: 'picker cancelled');
    final tree = picked!.uri;
    debugPrint('>>> Picked "${picked.name}": $tree');
    expect(await api.hasAccess(tree), isTrue);
    expect((await api.describe(tree)).name, picked.name);

    final root = 'sasa-device-test-${Random().nextInt(1 << 30)}';
    final f = SafSyncFolder(api, tree);

    // Basic file operations.
    expect(await f.list(root), isEmpty);
    expect(await f.read('$root/missing.json'), isNull);
    await f.write('$root/a/config.json', '{"a":1}');
    await f.write('$root/a/config.json', '{"b":2}');
    expect(await f.read('$root/a/config.json'), '{"b":2}');
    await f.append('$root/a/log.jsonl', 'one\n');
    await f.append('$root/a/log.jsonl', 'Réseaux ⏱\n');
    expect(await f.read('$root/a/log.jsonl'), 'one\nRéseaux ⏱\n');
    // Names are kept exactly: no ".txt" or "(1)" added by the provider.
    expect((await f.list('$root/a')).map((e) => e.name), [
      'config.json',
      'log.jsonl',
    ]);
    expect(
      (await f.list(root)).single,
      const FolderEntry('a', isDirectory: true),
    );
    await f.delete('$root/a/config.json');
    expect(await f.read('$root/a/config.json'), isNull);
    await expectLater(f.read('../escape'), throwsArgumentError);

    // Concurrent appends to one new file: one file, every line whole.
    final sw = Stopwatch()..start();
    await Future.wait([
      for (var i = 0; i < 100; i++) f.append('$root/c/log.jsonl', 'line-$i\n'),
    ]);
    debugPrint('>>> 100 concurrent appends: ${sw.elapsedMilliseconds} ms');
    expect((await f.list('$root/c')).map((e) => e.name), ['log.jsonl']);
    final lines = (await f.read('$root/c/log.jsonl'))!.trim().split('\n');
    expect(lines.toSet(), {for (var i = 0; i < 100; i++) 'line-$i'});

    // Event log from two device ids, a torn line, and config conflicts.
    final clock = FakeClock(DateTime.utc(2026, 11, 8, 9));
    final sasa = SasaFolder(f, root: root);
    final phone = sasa.eventLog(deviceId: 'android-test', clock: clock);
    final laptop = sasa.eventLog(deviceId: 'linux-test', clock: clock);
    for (var i = 0; i < 30; i++) {
      await phone.append(
        SuggestionSkipped(activityId: 'p$i', categoryId: 'reading'),
      );
      await laptop.append(const EnergyCheckin(energy: Energy.medium));
      clock.advance(const Duration(minutes: 1));
    }
    await f.append(
      '$root/devices/android-test/log-2026-11.jsonl',
      '{"id":"torn',
    );
    await sasa
        .eventLog(deviceId: 'android-test', clock: clock)
        .append(const EnergyCheckin(energy: Energy.high));
    sw.reset();
    final snap = await phone.load();
    debugPrint('>>> Event log load: ${sw.elapsedMilliseconds} ms');
    expect(snap.devices, ['android-test', 'linux-test']);
    expect(snap.events, hasLength(61));
    expect(snap.issues, hasLength(1));
    expect(snap.state.skips, hasLength(30));
    expect(snap.state.latestEnergy!.energy, Energy.high);

    final config = await sasa.loadOrCreateConfig(clock);
    await f.write(
      '$root/config.sync-conflict-20261108-090000-TESTDEV.json',
      jsonEncode(
        config
            .copyWith(updatedAt: clock.now().add(const Duration(hours: 1)))
            .toJson(),
      ),
    );
    expect(await sasa.configConflicts(), hasLength(1));
    final kept = await sasa.keepNewestConfig();
    expect(kept.updatedAt, clock.now().add(const Duration(hours: 1)));
    expect(await sasa.configConflicts(), isEmpty);

    // Leave a marker for phase 2 and remember the tree.
    await f.write('$root/marker.txt', 'phase 1 ok');
    final prefs = SharedPreferencesAsync();
    await prefs.setString(treeKey, tree);
    await prefs.setString(rootKey, root);
    debugPrint('>>> Phase 1 done. Test data is in "${picked.name}/$root".');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
