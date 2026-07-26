import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain / Keystore-backed storage for the handful of values that must never
/// touch the Drift file or a backup: AI API keys, the local encryption key, the
/// refresh token.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

class PlatformSecureStore implements SecureStore {
  PlatformSecureStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();
}

abstract final class SecureKeys {
  const SecureKeys._();

  /// Per-provider API key, e.g. `ai.key.openai`.
  static String aiKey(String providerId) => 'ai.key.$providerId';

  static const String dbEncryptionKey = 'db.encryption_key';
  static const String backupPassphrase = 'backup.passphrase';
  static const String appLockSalt = 'lock.salt';
}
