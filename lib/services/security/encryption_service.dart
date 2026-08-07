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
  static const int _saltLength = 16;

  /// PBKDF2 rounds for passphrase-derived keys. Written into every envelope so
  /// this can be raised later without orphaning existing backups.
  static const int _iterations = 120000;

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

  /// Derives a key from a user passphrase and a per-file salt.
  ///
  /// The salt travels inside the envelope rather than living in the keychain.
  /// That is the difference between a backup and a hostage: a keychain salt is
  /// device-local, so the file would only ever open on the phone that wrote it
  /// — and not even there after a reinstall.
  enc.Key _passphraseKey(
    String passphrase,
    List<int> salt, {
    int iterations = _iterations,
  }) =>
      enc.Key(
        _pbkdf2(
          password: utf8.encode(passphrase),
          salt: salt,
          iterations: iterations,
          length: _keyLength,
        ),
      );

  /// The pre-salt derivation, kept only so backups written by earlier builds
  /// still open on the device that made them.
  Future<enc.Key> _legacyPassphraseKey(String passphrase) async {
    final salt = await _store.read(SecureKeys.appLockSalt);
    if (salt == null) {
      throw const ValidationFailure(
        'That backup was made on another device and cannot be opened here.',
      );
    }
    final digest = sha256.convert(utf8.encode('$salt:$passphrase'));
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  Future<Result<String>> encrypt(String plaintext, {String? passphrase}) =>
      Result.guard(() async {
        final random = Random.secure();
        final salt = List<int>.generate(
          _saltLength,
          (_) => random.nextInt(256),
        );
        final key = passphrase == null
            ? await _deviceKey()
            : _passphraseKey(passphrase, salt);
        final iv = enc.IV.fromSecureRandom(_ivLength);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
        final encrypted = encrypter.encrypt(plaintext, iv: iv);

        // Neither the IV nor the salt is secret, and both must travel with the
        // ciphertext for it to be readable anywhere else.
        return jsonEncode(<String, dynamic>{
          'v': 2,
          'iv': iv.base64,
          if (passphrase != null) 'salt': base64Encode(salt),
          if (passphrase != null) 'iter': _iterations,
          'data': encrypted.base64,
        });
      }, onError: (e, s) => UnknownFailure(
            message: 'Could not encrypt the backup.',
            cause: e,
          ));

  Future<Result<String>> decrypt(String envelope, {String? passphrase}) =>
      Result.guard(() async {
        final Map<String, dynamic> json;
        try {
          json = jsonDecode(envelope) as Map<String, dynamic>;
        } catch (_) {
          throw const ValidationFailure('That file is not a LifeOS backup.');
        }

        final enc.Key key;
        if (passphrase == null) {
          key = await _deviceKey();
        } else if (json['salt'] is String) {
          key = _passphraseKey(
            passphrase,
            base64Decode(json['salt'] as String),
            iterations: json['iter'] as int? ?? _iterations,
          );
        } else {
          key = await _legacyPassphraseKey(passphrase);
        }

        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
        return encrypter.decrypt64(
          json['data'] as String,
          iv: enc.IV.fromBase64(json['iv'] as String),
        );
      }, onError: (e, s) => e is Failure
          ? e
          : const ValidationFailure(
              'That backup could not be opened. Check the passphrase.',
            ));

  /// PBKDF2-HMAC-SHA256, RFC 8018 §5.2.
  ///
  /// Written out rather than added as a dependency: `crypto` already supplies
  /// the HMAC, and the loop below is the entire algorithm. A single hash of the
  /// passphrase — which is what this replaced — is brute-forceable at billions
  /// of guesses a second against a file the attacker already holds.
  static Uint8List _pbkdf2({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int length,
  }) {
    final hmac = Hmac(sha256, password);
    final output = <int>[];

    for (var block = 1; output.length < length; block++) {
      var u = hmac.convert(<int>[
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ]).bytes;
      final accumulated = List<int>.of(u);

      for (var round = 1; round < iterations; round++) {
        u = hmac.convert(u).bytes;
        for (var i = 0; i < accumulated.length; i++) {
          accumulated[i] ^= u[i];
        }
      }
      output.addAll(accumulated);
    }

    return Uint8List.fromList(output.sublist(0, length));
  }

  /// Stable, non-reversible id for cache keys built from user content.
  static String hash(String input) =>
      sha256.convert(utf8.encode(input)).toString().substring(0, 16);
}

final Provider<EncryptionService> encryptionServiceProvider =
    Provider<EncryptionService>(
  (ref) => EncryptionService(ref.watch(secureStoreProvider)),
);
