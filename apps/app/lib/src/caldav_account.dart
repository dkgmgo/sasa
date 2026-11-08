import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sasa_caldav/sasa_caldav.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'secret_store.dart';
import 'setup_controller.dart';

/// Shared HTTP client for CalDAV.
final http.Client _http = http.Client();

CalDavClient _client(CalDavAccount a) => CalDavClient(
  baseUri: a.url,
  httpClient: _http,
  credentials: CalDavCredentials(a.username, a.password),
);

/// The CalDAV source for the stored account, or null when none is stored.
Future<CalendarSource?> calDavSourceFrom(
  SecretStore secrets,
  tz.Location zone,
) async {
  final account = await secrets.calDavAccount();
  if (account == null) return null;
  return CalDavSource(client: _client(account), zones: ZoneResolver(zone));
}

/// [CalDavTester]: discovers the account's collections.
Future<String> testCalDavAccount(CalDavAccount account) async {
  try {
    final collections = await _client(account)
        .discoverCollections()
        .timeout(const Duration(seconds: 20));
    final events = collections.where((c) => c.hasEvents).length;
    final tasks = collections.where((c) => c.hasTasks).length;
    return 'Connected: $events calendar${events == 1 ? '' : 's'}, '
        '$tasks task list${tasks == 1 ? '' : 's'}.';
  } on CalDavAuthException {
    throw const ConnectionFailed('Wrong user name or password.');
  } on CalDavException catch (e) {
    throw ConnectionFailed(
      e.statusCode == null
          ? 'No CalDAV server found at this URL.'
          : 'The server answered HTTP ${e.statusCode}.',
    );
  } on TimeoutException {
    throw const ConnectionFailed('The server did not answer in time.');
  } on SocketException catch (e) {
    throw ConnectionFailed('Cannot reach the server (${e.message}).');
  } on HandshakeException {
    throw const ConnectionFailed(
      'Secure connection failed (certificate problem?).',
    );
  } on http.ClientException catch (e) {
    throw ConnectionFailed('Connection failed (${e.message}).');
  }
}
