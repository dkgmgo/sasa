import 'dart:convert';
import 'dart:io';

import 'package:sasa_core/sasa_core.dart';

/// Reads the app's secure-store entry; null when there is none.
typedef Keyring = Future<Map<String, String>?> Function();

/// Runs a process (injected for tests).
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> args,
);

/// libsecret attribute under which the Linux app (flutter_secure_storage)
/// keeps its secrets, as one JSON object.
const keyringAccount = 'fr.dkgmgo.sasa.secureStorage';

/// [Keyring] backed by `secret-tool` (libsecret's CLI). Any failure (tool
/// missing, keyring locked, no entry) reads as "no entry".
Keyring secretToolKeyring({RunProcess? run}) => () async {
  final runner = run ?? Process.run;
  try {
    final r = await runner('secret-tool', [
      'lookup',
      'account',
      keyringAccount,
    ]);
    if (r.exitCode != 0) return null;
    final decoded = jsonDecode('${r.stdout}'.trim());
    if (decoded is! Map<String, Object?>) return null;
    return {
      for (final e in decoded.entries)
        if (e.value is String) e.key: e.value! as String,
    };
  } on ProcessException {
    return null;
  } on FormatException {
    return null;
  }
};

/// Where the CLI found (or did not find) the CalDAV account.
final class SecretLookup {
  const SecretLookup(this.account, this.source, this.warnings);

  final CalDavAccount? account;

  /// `environment`, the env file's path, or `keyring`.
  final String? source;
  final List<String> warnings;
}

/// Default env file: `$XDG_CONFIG_HOME/sasa/secrets.env`, else
/// `~/.config/sasa/secrets.env`.
String? defaultEnvFile(Map<String, String> env) {
  final xdg = env['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) return '$xdg/sasa/secrets.env';
  final home = env['HOME'];
  if (home == null || home.isEmpty) return null;
  return '$home/.config/sasa/secrets.env';
}

/// Finds the CalDAV account: process environment, then the env file at
/// [envFilePath], then the app's [keyring] entry.
///
/// An env file inside [syncFolder] is refused: secrets never go in the
/// synced folder.
Future<SecretLookup> findCalDavAccount({
  required Map<String, String> env,
  required String? envFilePath,
  required Keyring keyring,
  String? syncFolder,
}) async {
  final warnings = <String>[];
  final fromEnv = calDavAccountFromEnv(env);
  if (fromEnv != null) return SecretLookup(fromEnv, 'environment', warnings);

  if (envFilePath != null) {
    final file = File(envFilePath);
    if (file.existsSync()) {
      if (syncFolder != null && _isInside(file.absolute.path, syncFolder)) {
        warnings.add(
          'Ignoring $envFilePath: it is inside the synced folder, and '
          'secrets must not be synced. Move it to ~/.config/sasa/.',
        );
      } else {
        if (file.statSync().mode & 0x3f != 0) {
          warnings.add(
            '$envFilePath is readable by other users; run chmod 600 on it.',
          );
        }
        final account = calDavAccountFromEnv(
          parseEnvFile(file.readAsStringSync()),
        );
        if (account != null) {
          return SecretLookup(account, envFilePath, warnings);
        }
      }
    }
  }

  final stored = await keyring();
  final fromKeyring = stored == null ? null : CalDavAccount.fromSecrets(stored);
  if (fromKeyring != null) {
    return SecretLookup(fromKeyring, 'keyring', warnings);
  }
  return SecretLookup(null, null, warnings);
}

bool _isInside(String path, String folder) {
  final dir = Directory(folder).absolute.path;
  final prefix = dir.endsWith('/') ? dir : '$dir/';
  return path.startsWith(prefix);
}
