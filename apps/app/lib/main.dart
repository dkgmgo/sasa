import 'dart:io';

import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter/material.dart';
import 'package:saf_folder/saf_folder.dart';
import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'src/caldav_account.dart';
import 'src/data_controller.dart';
import 'src/device_settings.dart';
import 'src/folder_access.dart';
import 'src/secret_store.dart';
import 'src/settings_screen.dart';
import 'src/setup_controller.dart';
import 'src/setup_screen.dart';
import 'src/source_controller.dart';
import 'src/source_setup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = currentSourcePlatform();
  final isAndroid = platform == SourcePlatform.android;
  final deviceFilePath = isAndroid
      ? null
      : DeviceFile.defaultPath(Platform.environment);
  final settings = PrefsDeviceSettings(
    deviceFile: deviceFilePath == null ? null : DeviceFile(deviceFilePath),
    idPrefix: isAndroid ? 'android' : platform.name,
  );
  final secrets = SecureSecretStore();
  final zone = locationFor(defaultTimeZone);
  final clock = FunctionClock(DateTime.now);
  runApp(
    SasaApp(
      services: AppServices(
        platform: platform,
        settings: settings,
        secrets: secrets,
        access: isAndroid ? SafFolderAccess(SafFolder()) : PathFolderAccess(),
        clock: clock,
        bridge: DavxBridge(),
        calDav: () => calDavSourceFrom(secrets, zone),
        testCalDav: testCalDavAccount,
        zone: zone,
      ),
    ),
  );
}

/// Everything the screens need, built once.
final class AppServices {
  AppServices({
    required this.platform,
    required this.settings,
    required this.secrets,
    required this.access,
    required Clock clock,
    required DavxBridgeApi bridge,
    required CalDavFactory calDav,
    required this.zone,
    this.testCalDav,
  }) : data = DataController(settings: settings, access: access, clock: clock),
       sources = SourceController(
         platform: platform,
         settings: settings,
         bridge: bridge,
         zone: zone,
         calDav: calDav,
       );

  final SourcePlatform platform;
  final DeviceSettings settings;
  final SecretStore secrets;
  final FolderAccess access;
  final DataController data;
  final SourceController sources;
  final CalDavTester? testCalDav;
  final tz.Location zone;

  SetupController setup() => SetupController(
    platform: platform,
    settings: settings,
    secrets: secrets,
    access: access,
    data: data,
    sources: sources,
    testCalDav: testCalDav,
  );

  /// True when setup is done and the saved folder opened.
  Future<bool> start() async {
    if (!await settings.setupDone()) return false;
    final opened = await data.openSaved();
    if (opened) await sources.refresh();
    return opened;
  }
}

/// Root widget of the Sasa app.
class SasaApp extends StatelessWidget {
  const SasaApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'Sasa',
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: RootScreen(services: services),
    );
  }
}

/// Shows setup until it is done and the folder can be opened, then home.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  late final Future<bool> _started = widget.services.start();
  bool _setupJustDone = false;

  void _setupDone() {
    setState(() {
      _setupJustDone = true;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _started,
    builder: (context, snap) {
      if (!snap.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final s = widget.services;
      if (!snap.data! && !_setupJustDone && !s.data.accessLost) {
        return SetupScreen(controller: s.setup(), onDone: _setupDone);
      }
      return HomeScreen(services: s);
    },
  );
}

/// Temporary home screen until the Today screen exists: greeting, folder
/// status and problems that need the user.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.services});

  final AppServices services;

  void _openSetup(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (route) => SetupScreen(
        controller: services.setup(),
        firstRun: false,
        onDone: () => Navigator.of(route).pop(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = services.data;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(
                  controller: services.sources,
                  data: data,
                  onEditSetup: () => _openSetup(context),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: data,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (data.accessLost)
              _Banner(
                icon: Icons.folder_off_outlined,
                text:
                    'Sasa can no longer open "${data.location?.name ?? 'the '
                            'synced folder'}". Choose it again.',
                action: 'Choose folder',
                onAction: () => _openSetup(context),
              ),
            if (data.conflicts.isNotEmpty)
              _Banner(
                icon: Icons.call_split,
                text:
                    'Your sync app made ${data.conflicts.length} conflicting '
                    'cop${data.conflicts.length == 1 ? 'y' : 'ies'} of '
                    'config.json. Keep the most recently changed version?',
                action: 'Keep newest',
                onAction: data.busy ? null : data.keepNewestConfig,
              ),
            if (data.error != null)
              _Banner(icon: Icons.error_outline, text: data.error!),
            const SizedBox(height: 24),
            Text(
              sasaGreeting,
              style: theme.textTheme.displayMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              placeholderMessage(),
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (data.isOpen) FolderStatus(data: data),
          ],
        ),
      ),
    );
  }
}

/// One line about the synced folder and the merged logs.
class FolderStatus extends StatelessWidget {
  const FolderStatus({super.key, required this.data});

  final DataController data;

  @override
  Widget build(BuildContext context) {
    final snap = data.snapshot;
    final devices = snap?.devices.length ?? 0;
    final events = snap?.events.length ?? 0;
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(data.location!.name),
      subtitle: Text(
        '$events event${events == 1 ? '' : 's'} from $devices '
        'device${devices == 1 ? '' : 's'}'
        '${(snap?.newerVersionEvents ?? 0) > 0 ? ' · some need a newer Sasa' : ''}',
      ),
      trailing: IconButton(
        tooltip: 'Reload',
        icon: const Icon(Icons.refresh),
        onPressed: data.busy ? null : data.reload,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    ),
  );
}
