import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/security/secure_store.dart';

/// AES-256-GCM for exported backups.
///
/// Scope is deliberate: this encrypts *files that leave the device*. Data at
/// rest inside the app is protected by the OS sandbox, and can additionally be
/// protected with SQLCipher (see docs/DEPLOYMENT.md) — mixing the two concerns
/// in one class is how key-management mistakes happen.
class EncryptionService {
  const EncryptionService(this._store);

  final SecureStore _store;

  static const int _keyLength = 32;
  static const int _ivLength = 12;

  /// Returns the device key, generating and storing one on first use.
  Future<enc.Key> _deviceKey() async {
    final existing = await _store.read(SecureKeys.dbEncryptionKey);
    if (existing != null) return enc.Key.fromBase64(existing);

    final random = Random.secure();
    final bytes = List<int>.generate(_keyLength, (_) => random.nextInt(256));
    final key = enc.Key(Uint8List.fromList(bytes));
    await _store.write(SecureKeys.dbEncryptionKey, key.base64);
    return key;
  }

  /// Derives a key from a user passphrase.
  ///
  /// PBKDF2 would be better and is a drop-in change; SHA-256 with a stored salt
  /// is used here to avoid pulling in another dependency for the reference
  /// implementation. This is called out in docs/DEPLOYMENT.md.
  Future<enc.Key> _passphraseKey(String passphrase) async {
    var salt = await _store.read(SecureKeys.appLockSalt);
    if (salt == null) {
      final random = Random.secure();
      salt = base64Encode(
        List<int>.generate(16, (_) => random.nextInt(256)),
      );
      await _store.write(SecureKeys.appLockSalt, salt);
    }
    final digest = sha256.convert(utf8.encode('$salt:$passphrase'));
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  Future<Result<String>> encrypt(String plaintext, {String? passphrase}) =>
      Result.guard(() async {
        final key = passphrase == null
            ? await _deviceKey()
            : await _passphraseKey(passphrase);
        final iv = enc.IV.fromSecureRandom(_ivLength);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
        final encrypted = encrypter.encrypt(plaintext, iv: iv);

        // The IV is not secret and must travel with the ciphertext.
        return jsonEncode(<String, String>{
          'v': '1',
          'iv': iv.base64,
          'data': encrypted.base64,
        });
      }, onError: (e, s) => UnknownFailure(
            message: 'Could not encrypt the backup.',
            cause: e,
          ));

  Future<Result<String>> decrypt(String envelope, {String? passphrase}) =>
      Result.guard(() async {
        final json = jsonDecode(envelope) as Map<String, dynamic>;
        final key = passphrase == null
            ? await _deviceKey()
            : await _passphraseKey(passphrase);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));

        return encrypter.decrypt64(
          json['data'] as String,
          iv: enc.IV.fromBase64(json['iv'] as String),
        );
      }, onError: (e, s) => const ValidationFailure(
            'That backup could not be opened. Check the passphrase.',
          ));

  /// Stable, non-reversible id for cache keys built from user content.
  static String hash(String input) =>
      sha256.convert(utf8.encode(input)).toString().substring(0, 16);
}

final Provider<EncryptionService> encryptionServiceProvider =
    Provider<EncryptionService>(
  (ref) => EncryptionService(ref.watch(secureStoreProvider)),
);
