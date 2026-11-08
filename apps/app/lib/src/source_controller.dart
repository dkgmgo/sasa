import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'device_settings.dart';
import 'source_setup.dart';

/// Holds the current [SourceSetup] for the UI and rebuilds it when the
/// setting or the permissions change.
final class SourceController extends ChangeNotifier {
  SourceController({
    required this.platform,
    required this.settings,
    required this.bridge,
    required this.zone,
    this.calDav,
  });

  final SourcePlatform platform;
  final DeviceSettings settings;
  final DavxBridgeApi bridge;
  final tz.Location zone;
  final CalendarSource? calDav;

  SourceSetup? _setup;
  bool _forceCalDav = false;
  bool _busy = false;

  SourceSetup? get setup => _setup;
  bool get forceCalDav => _forceCalDav;
  bool get busy => _busy;
  bool get isAndroid => platform == SourcePlatform.android;

  /// True when a permission prompt could unlock the DAVx⁵ provider.
  bool get canRequestAccess {
    final s = _setup?.status;
    if (!isAndroid || s == null) return false;
    return !s.calendarPermission ||
        (s.taskAuthority != null && !s.taskPermission);
  }

  Future<void> refresh() => _run(() async {
    _forceCalDav = await settings.forceCalDav();
    _setup = await setUpSource(
      platform: platform,
      settings: settings,
      bridge: bridge,
      zone: zone,
      calDav: calDav,
    );
  });

  Future<void> setForceCalDav(bool value) async {
    await settings.setForceCalDav(value);
    await refresh();
  }

  /// Shows the system permission prompt, then re-selects the source.
  Future<void> requestAccess() async {
    try {
      await bridge.requestPermissions();
    } on Exception {
      // No prompt possible (no plugin, a prompt already showing): refresh
      // shows the current state.
    }
    await refresh();
  }

  Future<void> _run(Future<void> Function() work) async {
    _busy = true;
    notifyListeners();
    try {
      await work();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
