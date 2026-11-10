import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:sasa_cli/sasa_cli.dart';
import 'package:test/test.dart';

/// A notification server on a private bus, recording `Notify` calls.
final class _Server extends DBusObject {
  _Server() : super(DBusObjectPath('/org/freedesktop/Notifications'));

  final calls = <List<DBusValue>>[];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == 'org.freedesktop.Notifications' &&
        call.name == 'Notify') {
      calls.add(call.values);
      return DBusMethodSuccessResponse([DBusUint32(calls.length)]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

void main() {
  late Directory tmp;
  late DBusServer bus;
  late DBusAddress address;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sasa-dbus-');
    bus = DBusServer();
    address = await bus.listenAddress(DBusAddress.unix(dir: tmp));
  });
  tearDown(() async {
    await bus.close();
    await tmp.delete(recursive: true);
  });

  test('sends Notify with summary and escaped body', () async {
    final service = DBusClient(address);
    final server = _Server();
    await service.requestName('org.freedesktop.Notifications');
    await service.registerObject(server);

    await DbusNotifier(address: address)
        .notify('Sasa! Mon 9 Nov', 'Due: <draft> & co');

    final v = server.calls.single;
    expect(v[0], const DBusString('Sasa'));
    expect(v[1], const DBusUint32(0));
    expect(v[3], const DBusString('Sasa! Mon 9 Nov'));
    expect(v[4], const DBusString('Due: &lt;draft&gt; &amp; co'));
    expect(v[7], const DBusInt32(-1));
    await service.close();
  });

  test('no notification server is a NotifyFailed', () async {
    await expectLater(
      DbusNotifier(address: address).notify('a', 'b'),
      throwsA(isA<NotifyFailed>()),
    );
  });

  test('no bus at all is a NotifyFailed', () async {
    await expectLater(
      DbusNotifier(address: DBusAddress.unix(path: '${tmp.path}/missing'))
          .notify('a', 'b'),
      throwsA(isA<NotifyFailed>()),
    );
  });
}
