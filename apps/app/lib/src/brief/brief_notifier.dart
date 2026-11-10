import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Id of the (single) scheduled brief notification.
const int briefNotificationId = 1;

/// Payload of the brief notification: tapping it opens Today.
const String briefPayload = 'today';

/// Shows and schedules the brief notification (Android).
abstract interface class BriefNotifier {
  /// Prepares the plugin; [onOpenToday] runs when the user taps the brief
  /// while the app is running.
  Future<void> init({void Function()? onOpenToday});

  /// Schedules the brief at [at], replacing any scheduled one. Exact when
  /// the system allows it (see [canScheduleExact]), else within a window.
  Future<void> schedule({
    required String title,
    required String body,
    required tz.TZDateTime at,
    required bool exact,
  });

  /// Removes the scheduled brief, if any.
  Future<void> cancel();

  /// True when a brief is scheduled and has not fired yet.
  Future<bool> hasScheduled();

  /// True when exact alarms are allowed (Android 12+ may deny them).
  Future<bool> canScheduleExact();

  /// Opens the system screen to allow exact alarms.
  Future<void> requestExact();

  /// True when notifications are allowed (Android 13+ asks at runtime).
  Future<bool> enabled();

  /// Shows the notification permission prompt; true when granted.
  Future<bool> requestPermission();
}

/// [BriefNotifier] on `flutter_local_notifications`.
final class LocalBriefNotifier implements BriefNotifier {
  LocalBriefNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> init({void Function()? onOpenToday}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload == briefPayload) onOpenToday?.call();
      },
    );
  }

  @override
  Future<void> schedule({
    required String title,
    required String body,
    required tz.TZDateTime at,
    required bool exact,
  }) => _plugin.zonedSchedule(
    id: briefNotificationId,
    scheduledDate: at,
    title: title,
    body: body,
    payload: briefPayload,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'brief',
        'Morning brief',
        channelDescription: 'Your day, at the brief time',
        icon: 'ic_notification',
        category: AndroidNotificationCategory.reminder,
        // Collapsed: the first line; expanded: the whole brief.
        styleInformation: BigTextStyleInformation(body),
      ),
    ),
    androidScheduleMode: exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle,
  );

  @override
  Future<void> cancel() => _plugin.cancel(id: briefNotificationId);

  @override
  Future<bool> hasScheduled() async =>
      (await _plugin.pendingNotificationRequests()).any(
        (r) => r.id == briefNotificationId,
      );

  @override
  Future<bool> canScheduleExact() async =>
      await _android?.canScheduleExactNotifications() ?? false;

  @override
  Future<void> requestExact() async {
    await _android?.requestExactAlarmsPermission();
  }

  @override
  Future<bool> enabled() async =>
      await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;
}
