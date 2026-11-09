import 'package:flutter/material.dart';

import 'device_settings.dart';

/// The theme chosen on this device: system, light or dark.
final class ThemeController extends ValueNotifier<ThemeMode> {
  /// Starts at [initial] (read before the first frame to avoid a flash);
  /// without it, starts with the system theme and loads the saved choice.
  ThemeController(this.settings, {ThemeMode? initial})
    : super(initial ?? ThemeMode.system) {
    if (initial == null) _load();
  }

  final DeviceSettings settings;

  Future<void> _load() async => value = await settings.themeMode();

  Future<void> choose(ThemeMode mode) async {
    value = mode;
    await settings.setThemeMode(mode);
  }
}
