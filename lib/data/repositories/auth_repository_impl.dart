import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/cache/key_value_store.dart';
import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/app_database.dart';
import '../remote/supabase_bootstrap.dart';

/// Authentication with a hard offline-first rule: the cached session is
/// authoritative for *getting in*, and the network is only consulted to refresh
/// or change it. A user who cannot reach Supabase still opens straight into
/// their data.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._cache, this._db) {
    _controller = StreamController<AuthState>.broadcast(
      onListen: () => _controller.add(_state),
    );
    _bindRemote();
  }

  final KeyValueStore _cache;
  final AppDatabase _db;

  late final StreamController<AuthState> _controller;
  StreamSubscription<sb.AuthState>? _remoteSubscription;
  AuthState _state = const AuthState();

  sb.SupabaseClient? get _client => SupabaseBootstrap.clientOrNull;

  void _bindRemote() {
    final client = _client;
    if (client == null) return;
    _remoteSubscription = client.auth.onAuthStateChange.listen((event) {
      final session = event.session;
      if (session == null) {
        if (_state.user?.isLocalOnly ?? false) return;
        _emit(const AuthState());
      } else {
        _emit(
          _state.copyWith(
            user: _profileFrom(session.user),
            accessToken: session.accessToken,
            expiresAt: session.expiresAt == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000),
          ),
        );
      }
    });
  }

  UserProfile _profileFrom(sb.User user, {AuthMethod? method}) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return UserProfile(
      id: user.id,
      createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
      email: user.email ?? '',
      displayName: (metadata['full_name'] ?? metadata['name'] ?? '') as String,
      avatarUrl: metadata['avatar_url'] as String?,
      method: method ??
          switch (user.appMetadata['provider']) {
            'google' => AuthMethod.google,
            'apple' => AuthMethod.apple,
            _ => AuthMethod.email,
          },
    );
  }

  void _emit(AuthState next) {
    _state = next;
    _controller.add(next);
    unawaited(_persist(next));
  }

  Future<void> _persist(AuthState state) async {
    if (state.user == null) {
      await _cache.remove(CacheKeys.lastSession);
      return;
    }
    // Only the profile and expiry are cached here; the refresh token stays in
    // Supabase's own secure storage and is never written to this box.
    await _cache.setJson(CacheKeys.lastSession, <String, dynamic>{
      'user': state.user!.toJson(),
      'expiresAt': state.expiresAt?.toIso8601String(),
    });
  }

  @override
  Stream<AuthState> watchAuthState() => _controller.stream;

  @override
  Future<Result<AuthState>> restoreSession() => Result.guard(() async {
        final cached = _cache.getJson(CacheKeys.lastSession);
        if (cached != null) {
          final user =
              UserProfile.fromJson(cached['user'] as Map<String, dynamic>);
          final expiresAt = cached['expiresAt'] == null
              ? null
              : DateTime.tryParse(cached['expiresAt'] as String);
          _emit(AuthState(user: user, expiresAt: expiresAt));
        }

        // Then try to upgrade to a live session, without blocking on it.
        final client = _client;
        if (client != null) {
          final session = client.auth.currentSession;
          if (session != null) {
            _emit(
              AuthState(
                user: _profileFrom(session.user),
                accessToken: session.accessToken,
                expiresAt: session.expiresAt == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(
                        session.expiresAt! * 1000,
                      ),
              ),
            );
          }
        }
        return _state;
      });

  @override
  Future<Result<AuthState>> signInWithEmail({
    required String email,
    required String password,
  }) =>
      Result.guard(() async {
        final client = _requireClient();
        final response = await client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
        final user = response.user;
        if (user == null) {
          throw const AuthFailure('Could not sign in with those details.');
        }
        _emit(
          AuthState(
            user: _profileFrom(user, method: AuthMethod.email),
            accessToken: response.session?.accessToken,
          ),
        );
        return _state;
      }, onError: _authError);

  @override
  Future<Result<AuthState>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) =>
      Result.guard(() async {
        final client = _requireClient();
        final response = await client.auth.signUp(
          email: email.trim(),
          password: password,
          data: <String, dynamic>{'full_name': displayName},
        );
        final user = response.user;
        if (user == null) {
          throw const AuthFailure('Could not create that account.');
        }
        _emit(
          AuthState(
            user: _profileFrom(user, method: AuthMethod.email)
                .copyWith(displayName: displayName),
            accessToken: response.session?.accessToken,
          ),
        );
        return _state;
      }, onError: _authError);

  @override
  Future<Result<AuthState>> signInWithGoogle() => Result.guard(() async {
        final client = _requireClient();
        final googleSignIn = GoogleSignIn(
          scopes: const <String>['email', 'profile'],
        );
        final account = await googleSignIn.signIn();
        if (account == null) {
          throw const AuthFailure('Google sign-in was cancelled.');
        }
        final auth = await account.authentication;
        final idToken = auth.idToken;
        if (idToken == null) {
          throw const AuthFailure('Google did not return an identity token.');
        }

        final response = await client.auth.signInWithIdToken(
          provider: sb.OAuthProvider.google,
          idToken: idToken,
          accessToken: auth.accessToken,
        );
        final user = response.user;
        if (user == null) throw const AuthFailure('Google sign-in failed.');

        _emit(
          AuthState(
            user: _profileFrom(user, method: AuthMethod.google),
            accessToken: response.session?.accessToken,
          ),
        );
        return _state;
      }, onError: _authError);

  @override
  Future<Result<AuthState>> signInWithApple() => Result.guard(() async {
        final client = _requireClient();
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: <AppleIDAuthorizationScopes>[
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
        final idToken = credential.identityToken;
        if (idToken == null) {
          throw const AuthFailure('Apple did not return an identity token.');
        }

        final response = await client.auth.signInWithIdToken(
          provider: sb.OAuthProvider.apple,
          idToken: idToken,
        );
        final user = response.user;
        if (user == null) throw const AuthFailure('Apple sign-in failed.');

        // Apple only sends the name on the very first authorisation, so it is
        // captured here rather than read back from the token later.
        final name = <String?>[credential.givenName, credential.familyName]
            .whereType<String>()
            .join(' ')
            .trim();
        _emit(
          AuthState(
            user: _profileFrom(user, method: AuthMethod.apple).copyWith(
              displayName: name.isEmpty ? '' : name,
            ),
            accessToken: response.session?.accessToken,
          ),
        );
        return _state;
      }, onError: _authError);

  @override
  Future<Result<AuthState>> continueLocally({String displayName = ''}) =>
      Result.guard(() async {
        _emit(
          AuthState(
            user: UserProfile(
              id: newId(),
              createdAt: DateTime.now(),
              displayName: displayName,
              method: AuthMethod.local,
            ),
          ),
        );
        return _state;
      });

  @override
  Future<Result<void>> sendPasswordReset(String email) =>
      Result.guard(() async {
        await _requireClient().auth.resetPasswordForEmail(email.trim());
      }, onError: _authError);

  @override
  Future<Result<void>> signOut() => Result.guard(() async {
        try {
          await _client?.auth.signOut();
        } catch (error) {
          // Signing out locally must succeed even when the network refuses.
          AppLogger.warn('auth', 'Remote sign-out failed', error);
        }
        await _cache.remove(CacheKeys.lastSession);
        _emit(const AuthState());
      });

  @override
  Future<Result<void>> deleteAccount() => Result.guard(() async {
        // Local data goes first: if the remote call fails afterwards the user is
        // still left with nothing on the device, which is the safer failure.
        await _db.wipe();
        await _cache.clear();
        try {
          final client = _client;
          final userId = _state.user?.id;
          if (client != null && userId != null && !_state.user!.isLocalOnly) {
            await client.rpc<void>('delete_current_user');
          }
        } catch (error) {
          AppLogger.warn('auth', 'Remote account deletion failed', error);
        }
        _emit(const AuthState());
      });

  @override
  Future<Result<UserProfile>> updateProfile(UserProfile profile) =>
      Result.guard(() async {
        _emit(_state.copyWith(user: profile));
        final client = _client;
        if (client != null && !profile.isLocalOnly) {
          await client.auth.updateUser(
            sb.UserAttributes(
              data: <String, dynamic>{
                'full_name': profile.displayName,
                'focus_areas': profile.focusAreas,
              },
            ),
          );
        }
        return profile;
      });

  /// Locks the app behind the biometric gate without ending the session.
  void lock() => _emit(_state.copyWith(isLocked: true));

  void unlock() => _emit(_state.copyWith(isLocked: false));

  sb.SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const AuthFailure(
        'Cloud accounts are not configured in this build. '
        'You can keep using LifeOS on this device.',
      );
    }
    return client;
  }

  Failure _authError(Object error, StackTrace stackTrace) {
    if (error is sb.AuthException) {
      return AuthFailure(error.message, cause: error);
    }
    return AuthFailure(
      'Sign-in failed. Check your connection and try again.',
      cause: error,
    );
  }

  void dispose() {
    unawaited(_remoteSubscription?.cancel());
    unawaited(_controller.close());
  }
}
