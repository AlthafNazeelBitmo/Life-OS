import '../../core/error/result.dart';
import '../entities/user_profile.dart';

/// Authentication, with an offline-first contract.
///
/// [restoreSession] must succeed from cache with no network: a user who opens
/// the app on a plane still gets into their data. Remote validation happens
/// opportunistically afterwards.
abstract interface class AuthRepository {
  Stream<AuthState> watchAuthState();

  Future<Result<AuthState>> restoreSession();

  Future<Result<AuthState>> signInWithEmail({
    required String email,
    required String password,
  });

  Future<Result<AuthState>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  });

  Future<Result<AuthState>> signInWithGoogle();

  Future<Result<AuthState>> signInWithApple();

  /// Creates the on-device-only account. Chosen from onboarding by users who
  /// do not want a backend at all; everything works except sync.
  Future<Result<AuthState>> continueLocally({String displayName = ''});

  Future<Result<void>> sendPasswordReset(String email);

  Future<Result<void>> signOut();

  /// Wipes the remote account and every local row.
  Future<Result<void>> deleteAccount();

  Future<Result<UserProfile>> updateProfile(UserProfile profile);
}
