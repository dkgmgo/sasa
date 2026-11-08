/// Names and shapes of the secrets Sasa keeps outside the synced folder:
/// in the platform keyring (`flutter_secure_storage`; libsecret on Linux)
/// for the app, and the same keyring or an env file for the CLI.
library;

/// Keys in the secure store, shared by the app and the CLI.
abstract final class SecretKeys {
  static const calDavUrl = 'caldav.url';
  static const calDavUsername = 'caldav.username';
  static const calDavPassword = 'caldav.password';
}

/// CalDAV server and login. [toString] never shows the password.
final class CalDavAccount {
  const CalDavAccount({
    required this.url,
    required this.username,
    required this.password,
  });

  /// From the secure store's key/value map; null unless all parts are set.
  static CalDavAccount? fromSecrets(Map<String, String?> m) {
    final url = m[SecretKeys.calDavUrl];
    final user = m[SecretKeys.calDavUsername];
    final password = m[SecretKeys.calDavPassword];
    if (url == null || user == null || password == null) return null;
    if (url.isEmpty || user.isEmpty || password.isEmpty) return null;
    if (checkUrl(url) != null) return null;
    return CalDavAccount(
      url: Uri.parse(url),
      username: user,
      password: password,
    );
  }

  final Uri url;
  final String username;
  final String password;

  Map<String, String> toSecrets() => {
    SecretKeys.calDavUrl: url.toString(),
    SecretKeys.calDavUsername: username,
    SecretKeys.calDavPassword: password,
  };

  /// Null when [text] is a usable server URL, else a message for the user.
  static String? checkUrl(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'Enter the server URL';
    final u = Uri.tryParse(t);
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      return 'Enter a full URL, e.g. https://dav.example.org/';
    }
    if (u.scheme != 'https' && u.scheme != 'http') {
      return 'Use an http:// or https:// URL';
    }
    if (u.userInfo.isNotEmpty) {
      return 'Put the user name and password in their own fields, '
          'not in the URL';
    }
    return null;
  }

  /// True when the password would cross the network unencrypted.
  static bool isInsecure(Uri url) {
    if (url.scheme != 'http') return false;
    const local = {'localhost', '127.0.0.1', '::1', '[::1]'};
    return !local.contains(url.host);
  }

  @override
  bool operator ==(Object other) =>
      other is CalDavAccount &&
      other.url == url &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(url, username, password);

  @override
  String toString() => 'CalDavAccount($username @ $url, password ***)';
}

/// Environment variable names the CLI reads.
abstract final class SecretEnv {
  static const calDavUrl = 'SASA_CALDAV_URL';
  static const calDavUser = 'SASA_CALDAV_USER';
  static const calDavPassword = 'SASA_CALDAV_PASSWORD';
}

/// CalDAV account from environment-style variables (the process
/// environment or an env file); null unless all three are set.
CalDavAccount? calDavAccountFromEnv(Map<String, String> env) =>
    CalDavAccount.fromSecrets({
      SecretKeys.calDavUrl: env[SecretEnv.calDavUrl],
      SecretKeys.calDavUsername: env[SecretEnv.calDavUser],
      SecretKeys.calDavPassword: env[SecretEnv.calDavPassword],
    });

final _envLine = RegExp(r'^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$');

/// Parses a minimal `.env` file: `KEY=value`, optional `export`, single or
/// double quotes around the value, `#` comment lines. Other lines are
/// ignored. No variable expansion.
Map<String, String> parseEnvFile(String text) {
  final out = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final m = _envLine.firstMatch(line);
    if (m == null) continue;
    var value = m.group(2)!.trim();
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    out[m.group(1)!] = value;
  }
  return out;
}
