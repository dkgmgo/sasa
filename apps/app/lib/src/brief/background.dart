import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:saf_folder/saf_folder.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:workmanager/workmanager.dart';

import '../caldav_account.dart';
import '../data_controller.dart';
import '../device_settings.dart';
import '../folder_access.dart';
import '../secret_store.dart';
import '../source_setup.dart';
import 'brief_notifier.dart';
import 'brief_scheduler.dart';

/// Unique name of the hourly background tick (Android WorkManager).
const backgroundTickTask = 'fr.dkgmgo.sasa.tick';

/// How often the tick runs. WorkManager may delay it (Doze, battery saver).
const backgroundTickPeriod = Duration(hours: 1);

/// Registers the hourly tick. Safe to call on every start: an existing
/// registration keeps its schedule.
Future<void> registerBackgroundTick() async {
  await Workmanager().initialize(backgroundDispatcher);
  await Workmanager().registerPeriodicTask(
    backgroundTickTask,
    backgroundTickTask,
    frequency: backgroundTickPeriod,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// Entry point of WorkManager's background isolate.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      await runBackgroundTick();
    } on Object catch (e) {
      // Never the account: errors from the sources are log-safe.
      debugPrint('Sasa tick failed: ${e.runtimeType}');
    }
    // A failed tick is not retried early: the next one comes within the hour.
    return true;
  });
}

/// The tick's work, with the same building blocks as the app (no UI):
/// re-render and reschedule the next brief.
Future<void> runBackgroundTick({Clock? clock}) async {
  final c = clock ?? FunctionClock(DateTime.now);
  final settings = PrefsDeviceSettings(idPrefix: 'android');
  if (!await settings.setupDone()) return;
  final data = DataController(
    settings: settings,
    access: SafFolderAccess(SafFolder()),
    clock: c,
  );
  if (!await data.openSaved()) return;
  final config = data.config;
  if (config == null) return;
  final zone = locationOrDefault(config.timeZone);
  final setup = await setUpSource(
    platform: SourcePlatform.android,
    settings: settings,
    bridge: DavxBridge(),
    zone: zone,
    calDav: await calDavSourceFrom(SecureSecretStore(), zone),
  );
  final notifier = LocalBriefNotifier();
  await notifier.init();
  await BriefScheduler(
    notifier: notifier,
    clock: c,
  ).reschedule(config: config, source: setup.source, zone: zone);
}
