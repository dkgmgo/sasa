// Appends events to a device log from a separate process, for the
// concurrency tests: `dart run test/support/append_worker.dart <folder>
// <deviceId> <seed> <count>`.
import 'dart:io';
import 'dart:math';

import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';

Future<void> main(List<String> args) async {
  final [path, device, seed, count] = args;
  await appendMany(path, device, int.parse(seed), int.parse(count));
}

/// Appends [count] skips as [device], one simulated second apart.
///
/// Waits until a `.go` file exists in [path], so writers started at
/// different times all run at once.
Future<void> appendMany(String path, String device, int seed, int count) async {
  final go = File('$path/.go');
  while (!go.existsSync()) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  final clock = FakeClock(DateTime.utc(2026, 11, 8, 9));
  final log = EventLog(
    folder: IoSyncFolder(path),
    deviceId: device,
    clock: clock,
    random: Random(seed),
  );
  for (var i = 0; i < count; i++) {
    await log.append(
      SuggestionSkipped(activityId: '$device-$seed-$i', categoryId: 'c'),
    );
    clock.advance(const Duration(seconds: 1));
  }
}
