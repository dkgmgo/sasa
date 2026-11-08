import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sasa_core/sasa_core.dart';

/// Where this device keeps secrets: never the synced folder, never logs.
abstract interface class SecretStore {
  Future<CalDavAccount?> calDavAccount();

  /// Saves [account], or removes the stored one when null.
  Future<void> setCalDavAccount(CalDavAccount? account);
}

/// [SecretStore] in the platform keystore: Android Keystore-backed storage,
/// libsecret on Linux (where the `sasa` CLI can read the same entry).
final class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keys = [
    SecretKeys.calDavUrl,
    SecretKeys.calDavUsername,
    SecretKeys.calDavPassword,
  ];

  @override
  Future<CalDavAccount?> calDavAccount() async => CalDavAccount.fromSecrets({
    for (final k in _keys) k: await _storage.read(key: k),
  });

  @override
  Future<void> setCalDavAccount(CalDavAccount? account) async {
    if (account == null) {
      for (final k in _keys) {
        await _storage.delete(key: k);
      }
      return;
    }
    for (final MapEntry(:key, :value) in account.toSecrets().entries) {
      await _storage.write(key: key, value: value);
    }
  }
}

/// In-memory [SecretStore] for tests.
final class MemorySecretStore implements SecretStore {
  MemorySecretStore([this.account]);

  CalDavAccount? account;

  @override
  Future<CalDavAccount?> calDavAccount() async => account;

  @override
  Future<void> setCalDavAccount(CalDavAccount? value) async => account = value;
}
