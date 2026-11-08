import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/main.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:sasa/src/source_controller.dart';
import 'package:sasa_core/sasa_core.dart';

import 'fakes.dart';

void main() {
  final zone = locationFor('Europe/Paris');

  SourceController controller({
    SourcePlatform platform = SourcePlatform.android,
    FakeBridge? bridge,
    DeviceSettings? settings,
  }) => SourceController(
    platform: platform,
    settings: settings ?? MemoryDeviceSettings(),
    bridge: bridge ?? FakeBridge(),
    zone: zone,
  );

  Future<void> openSettings(WidgetTester tester, SourceController c) async {
    await tester.pumpWidget(SasaApp(sources: c));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
  }

  testWidgets('placeholder screen shows the greeting', (tester) async {
    await tester.pumpWidget(SasaApp(sources: controller()));
    expect(find.text(sasaGreeting), findsOneWidget);
    expect(find.text(placeholderMessage()), findsOneWidget);
  });

  testWidgets('settings show the DAVx⁵ source and toggle CalDAV', (
    tester,
  ) async {
    final settings = MemoryDeviceSettings();
    await openSettings(tester, controller(settings: settings));

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
    await openSettings(tester, controller(bridge: bridge));

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
      controller(bridge: FakeBridge(taskAuthority: null)),
    );
    expect(
      find.text('Tasks.org is not installed; tasks come from CalDAV.'),
      findsOneWidget,
    );
  });

  testWidgets('on Linux the toggle is fixed to CalDAV', (tester) async {
    await openSettings(tester, controller(platform: SourcePlatform.linux));
    expect(
      find.text('CalDAV is the only source on this platform.'),
      findsOneWidget,
    );
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNull);
    expect(find.text('Calendar access'), findsNothing);
  });
}
