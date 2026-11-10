import 'package:sasa_cli/sasa_cli.dart';

/// Records notifications instead of showing them.
final class FakeNotifier implements DesktopNotifier {
  final shown = <(String, String)>[];

  /// Throw [NotifyFailed] instead, like a session without a server.
  bool fail = false;

  @override
  Future<void> notify(String summary, String body) async {
    if (fail) throw const NotifyFailed('no server');
    shown.add((summary, body));
  }
}
