import 'dart:async';
import 'dart:io';

import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter/material.dart';
import 'package:saf_folder/saf_folder.dart';
import 'package:sasa_core/io.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'src/brief/background.dart';
import 'src/brief/brief_notifier.dart';
import 'src/brief/brief_scheduler.dart';
import 'src/caldav_account.dart';
import 'src/data_controller.dart';
import 'src/device_settings.dart';
import 'src/folder_access.dart';
import 'src/home_shell.dart';
import 'src/secret_store.dart';
import 'src/settings_screen.dart';
import 'src/setup_controller.dart';
import 'src/setup_screen.dart';
import 'src/source_controller.dart';
import 'src/source_setup.dart';
import 'src/theme/pwani.dart';
import 'src/theme_controller.dart';
import 'src/today_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();
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
  final themeMode = await settings.themeMode();
  BriefNotifier? notifier;
  if (isAndroid) {
    notifier = LocalBriefNotifier();
    try {
      await registerBackgroundTick();
    } on Exception catch (e) {
      debugPrint('Background tick not registered: $e');
    }
  }
  final services = AppServices(
    themeMode: themeMode,
    platform: platform,
    settings: settings,
    secrets: secrets,
    access: isAndroid ? SafFolderAccess(SafFolder()) : PathFolderAccess(),
    clock: clock,
    bridge: DavxBridge(),
    calDav: () => calDavSourceFrom(secrets, zone),
    testCalDav: testCalDavAccount,
    zone: zone,
    briefNotifier: notifier,
  );
  await notifier?.init(onOpenToday: services.openToday);
  runApp(SasaApp(services: services));
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
    ThemeMode? themeMode,
    BriefNotifier? briefNotifier,
  }) : theme = ThemeController(settings, initial: themeMode),
       data = DataController(settings: settings, access: access, clock: clock),
       sources = SourceController(
         platform: platform,
         settings: settings,
         bridge: bridge,
         zone: zone,
         calDav: calDav,
       ) {
    today = TodayController(
      data: data,
      sources: sources,
      clock: clock,
      fallbackZone: zone,
    );
    brief = briefNotifier == null
        ? null
        : BriefController(
            scheduler: BriefScheduler(notifier: briefNotifier, clock: clock),
            data: data,
            sources: sources,
            zone: () => today.zone,
          );
  }

  final SourcePlatform platform;
  final DeviceSettings settings;
  final SecretStore secrets;
  final FolderAccess access;
  final DataController data;
  final SourceController sources;
  late final TodayController today;

  /// Schedules the morning brief notification (Android; Linux uses the
  /// `sasa` timers). Null when not available.
  late final BriefController? brief;

  /// Navigator of the app, so a tapped brief can return to the home screen.
  final navigatorKey = GlobalKey<NavigatorState>();

  /// Bumped when the user tapped the brief: Home then shows Today.
  final todayRequests = ValueNotifier<int>(0);

  /// Brings the Today screen to the front.
  void openToday() {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    todayRequests.value++;
  }

  /// The app came back to the foreground.
  Future<void> resumed() async {
    if (data.isOpen) await brief?.refresh();
  }

  /// This device's choice of light, dark or system theme.
  final ThemeController theme;
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
    if (opened) {
      await sources.refresh();
      unawaited(_startBrief());
    }
    return opened;
  }

  Future<void> _startBrief() async {
    final b = brief;
    if (b == null) return;
    if (!await b.notifier.enabled()) await b.notifier.requestPermission();
    await b.refresh(force: true);
  }
}

/// Root widget of the Sasa app.
class SasaApp extends StatelessWidget {
  const SasaApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: services.theme,
      builder: (context, mode, _) => MaterialApp(
        navigatorKey: services.navigatorKey,
        title: 'Sasa',
        theme: pwaniTheme(Brightness.light),
        darkTheme: pwaniTheme(Brightness.dark),
        themeMode: mode,
        home: RootScreen(services: services),
      ),
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
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: widget.services.resumed);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

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

/// The main screens, with routes to settings and setup.
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
  Widget build(BuildContext context) => HomeShell(
    data: services.data,
    today: services.today,
    showToday: services.todayRequests,
    onOpenSetup: () => _openSetup(context),
    onOpenSettings: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          controller: services.sources,
          data: services.data,
          theme: services.theme,
          brief: services.brief,
          isLinux: services.platform == SourcePlatform.linux,
          onEditSetup: () => _openSetup(context),
        ),
      ),
    ),
  );
}
