import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';

/// Device-credential gate in front of the app.
///
/// This protects the *view*, not the data at rest — a stolen, unlocked phone is
/// a different threat from a stolen phone. Encryption of the database file is
/// handled separately by `EncryptionService`/SQLCipher.
class BiometricService {
  BiometricService([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> get isAvailable async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> enrolled() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const <BiometricType>[];
    }
  }

  Future<Result<bool>> authenticate({
    String reason = 'Unlock LifeOS',
  }) =>
      Result.guard(
        () => _auth.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(
            // Falling back to the device PIN matters: a user whose fingerprint
            // sensor fails must still be able to reach their own journal.
            biometricOnly: false,
            stickyAuth: true,
            useErrorDialogs: true,
          ),
        ),
        onError: (e, s) => const PermissionFailure(
          'Could not verify it is you.',
          permission: 'biometrics',
        ),
      );
}

final Provider<BiometricService> biometricServiceProvider =
    Provider<BiometricService>((ref) => BiometricService());
