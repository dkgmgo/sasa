import 'package:dbus/dbus.dart';

/// Shows a desktop notification.
abstract interface class DesktopNotifier {
  /// Shows [summary] with [body] (plain text).
  Future<void> notify(String summary, String body);
}

/// Thrown when no notification could be shown (no session bus, no
/// notification server).
final class NotifyFailed implements Exception {
  const NotifyFailed(this.message);
  final String message;

  @override
  String toString() => 'NotifyFailed: $message';
}

/// [DesktopNotifier] speaking the freedesktop.org notification protocol on
/// the session bus (`org.freedesktop.Notifications.Notify`).
final class DbusNotifier implements DesktopNotifier {
  /// [address] defaults to the session bus (`DBUS_SESSION_BUS_ADDRESS`).
  DbusNotifier({this.address});

  final DBusAddress? address;

  static const appName = 'Sasa';
  static const _name = 'org.freedesktop.Notifications';

  @override
  Future<void> notify(String summary, String body) async {
    final DBusClient client;
    try {
      client = switch (address) {
        null => DBusClient.session(introspectable: false),
        final a => DBusClient(a, introspectable: false),
      };
    } on Exception catch (e) {
      throw NotifyFailed('no session bus ($e)');
    }
    try {
      await DBusRemoteObject(
        client,
        name: _name,
        path: DBusObjectPath('/org/freedesktop/Notifications'),
      ).callMethod(_name, 'Notify', [
        const DBusString(appName),
        const DBusUint32(0), // replaces_id: a new notification
        const DBusString('x-office-calendar'),
        DBusString(summary),
        DBusString(escapeMarkup(body)),
        DBusArray.string(const []), // no actions
        DBusDict.stringVariant({'urgency': const DBusByte(1)}), // normal
        const DBusInt32(-1), // server's default timeout
      ], replySignature: DBusSignature('u'));
    } on DBusMethodResponseException catch (e) {
      throw NotifyFailed('the notification server refused (${e.errorName})');
    } on Exception catch (e) {
      throw NotifyFailed('$e');
    } finally {
      await client.close();
    }
  }
}

/// Servers may render a subset of HTML in the body: escape it so a task
/// called `<draft>` shows as typed.
String escapeMarkup(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
