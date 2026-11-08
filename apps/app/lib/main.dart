import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';

import 'src/device_settings.dart';
import 'src/settings_screen.dart';
import 'src/source_controller.dart';
import 'src/source_setup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    SasaApp(
      sources: SourceController(
        platform: currentSourcePlatform(),
        settings: PrefsDeviceSettings(),
        bridge: DavxBridge(),
        zone: locationFor(defaultTimeZone),
      ),
    ),
  );
}

/// Root widget of the Sasa app.
class SasaApp extends StatelessWidget {
  const SasaApp({super.key, required this.sources});

  final SourceController sources;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'Sasa',
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: PlaceholderScreen(sources: sources),
    );
  }
}

/// Temporary home screen shown until the Today screen exists.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.sources});

  final SourceController sources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(controller: sources),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(sasaGreeting, style: theme.textTheme.displayMedium),
              const SizedBox(height: 12),
              Text(
                placeholderMessage(),
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
