import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/main.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa/src/home_shell.dart';
import 'package:sasa/src/secret_store.dart';
import 'package:sasa/src/today_screen.dart';
import 'package:sasa_core/sasa_core.dart';

import 'fakes.dart';

void main() {
  // Tall enough that every setup section is built without scrolling.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(800, 2400);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  Future<void> openSettings(WidgetTester tester, AppServices s) async {
    await tester.pumpWidget(SasaApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
  }

  /// Services for a device that finished setup.
  AppServices ready({
    SourcePlatform platform = SourcePlatform.android,
    FakeBridge? bridge,
    DeviceSettings? settings,
    MemoryFolderAccess? access,
  }) => testServices(
    platform: platform,
    bridge: bridge,
    settings:
        settings ?? MemoryDeviceSettings(syncFolder: syncA, setupDone: true),
    access: access,
  );

  group('first run', () {
    testWidgets('shows setup, then home with the folder', (tester) async {
      final access = MemoryFolderAccess(nextPick: syncA);
      final settings = MemoryDeviceSettings();
      await tester.pumpWidget(
        SasaApp(
          services: testServices(settings: settings, access: access),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Set up Sasa'), findsOneWidget);
      expect(find.text('No folder chosen'), findsOneWidget);
      final finish = find.widgetWithText(FilledButton, 'Finish');
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);

      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.text('Sync'), findsOneWidget);
      expect(
        find.text('No Sasa data yet: it will be created.'),
        findsOneWidget,
      );
      expect(find.text('DAVx⁵ on this phone'), findsOneWidget);
      expect(find.text('3 · CalDAV account (optional)'), findsOneWidget);

      await tester.ensureVisible(finish);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(await settings.setupDone(), isTrue);
    });

    testWidgets('choosing CalDAV requires the account; password hidden', (
      tester,
    ) async {
      final secrets = MemorySecretStore();
      await tester.pumpWidget(
        SasaApp(
          services: testServices(
            secrets: secrets,
            access: MemoryFolderAccess(nextPick: syncA),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CalDAV server'));
      await tester.pumpAndSettle();
      expect(find.text('3 · CalDAV account'), findsOneWidget);
      expect(find.text('Complete the CalDAV account.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Server URL'),
        'https://dav.example.org/',
      );
      await tester.enterText(find.widgetWithText(TextField, 'User name'), 'me');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
      await tester.pumpAndSettle();
      final password = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Password'),
      );
      expect(password.obscureText, isTrue);

      final finish = find.widgetWithText(FilledButton, 'Finish');
      await tester.ensureVisible(finish);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(secrets.account, testAccount);
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('Linux has no source choice', (tester) async {
      await tester.pumpWidget(
        SasaApp(services: testServices(platform: SourcePlatform.linux)),
      );
      await tester.pumpAndSettle();
      expect(find.text('DAVx⁵ on this phone'), findsNothing);
      expect(find.text('2 · CalDAV account'), findsOneWidget);
    });
  });

  group('home', () {
    testWidgets('opens on Today; settings show the folder status', (
      tester,
    ) async {
      await tester.pumpWidget(SasaApp(services: ready()));
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('0 events from 0 devices'), findsOneWidget);
    });

    testWidgets('config conflict banner keeps the newest', (tester) async {
      final access = MemoryFolderAccess();
      await access
          .folder(syncA.ref)
          .write(
            'Sasa/config.sync-conflict-20261108-090000-ABCDEFG.json',
            '{"version":1}',
          );
      await tester.pumpWidget(SasaApp(services: ready(access: access)));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 conflicting copy'), findsOneWidget);
      await tester.tap(find.text('Keep newest'));
      await tester.pumpAndSettle();
      // The unreadable copy stays for the user to inspect.
      expect(find.textContaining('1 conflicting copy'), findsOneWidget);
    });

    testWidgets('a lost folder asks to choose it again', (tester) async {
      final access = MemoryFolderAccess()..accessible = false;
      await tester.pumpWidget(SasaApp(services: ready(access: access)));
      await tester.pumpAndSettle();
      expect(find.text('Choose folder'), findsOneWidget);
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      expect(find.text('Folder and account'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('show the DAVx⁵ source and toggle CalDAV', (tester) async {
      final settings = MemoryDeviceSettings(syncFolder: syncA, setupDone: true);
      await openSettings(tester, ready(settings: settings));

      expect(find.text('Synced folder'), findsOneWidget);
      expect(find.text('Source: DAVx⁵ on this device'), findsOneWidget);
      expect(find.text(SourceReason.davxAvailable.description), findsOneWidget);
      expect(find.text('Grant calendar and task access'), findsNothing);

      await tester.tap(find.text('Always use CalDAV'));
      await tester.pumpAndSettle();
      expect(await settings.forceCalDav(), isTrue);
      expect(find.text('Source: CalDAV'), findsOneWidget);
      expect(
        find.text(SourceReason.forcedInSettings.description),
        findsOneWidget,
      );
    });

    testWidgets('denied permission offers a grant button that re-selects', (
      tester,
    ) async {
      final bridge = FakeBridge(
        calendarPermission: false,
        taskPermission: false,
        grantOnRequest: true,
      );
      await openSettings(tester, ready(bridge: bridge));

      expect(find.text('Source: CalDAV'), findsOneWidget);
      expect(
        find.text(SourceReason.calendarPermissionDenied.description),
        findsOneWidget,
      );
      await tester.tap(find.text('Grant calendar and task access'));
      await tester.pumpAndSettle();

      expect(bridge.requests, 1);
      expect(find.text('Source: DAVx⁵ on this device'), findsOneWidget);
      expect(find.text('Grant calendar and task access'), findsNothing);
    });

    testWidgets('missing Tasks.org is explained', (tester) async {
      await openSettings(
        tester,
        ready(bridge: FakeBridge(taskAuthority: null)),
      );
      expect(
        find.text('Tasks.org is not installed; tasks come from CalDAV.'),
        findsOneWidget,
      );
    });

    testWidgets('on Linux the toggle is fixed to CalDAV', (tester) async {
      await openSettings(tester, ready(platform: SourcePlatform.linux));
      expect(
        find.text('CalDAV is the only source on this platform.'),
        findsOneWidget,
      );
      final toggle = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Always use CalDAV'),
      );
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNull);
      expect(find.text('Calendar access'), findsNothing);
    });

    testWidgets('folder tile opens the setup screen', (tester) async {
      await openSettings(tester, ready());
      await tester.tap(find.text('Synced folder'));
      await tester.pumpAndSettle();
      expect(find.text('Folder and account'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    });
  });
}
