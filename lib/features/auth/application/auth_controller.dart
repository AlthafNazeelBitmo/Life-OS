import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failures.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/user_profile.dart';
import '../../../services/security/biometric_service.dart';

/// Owns the session and the app lock.
///
/// The router reads this synchronously on every redirect, so it must settle
/// quickly: [build] restores from cache first and only then consults the
/// network, which is what makes a cold start offline land straight on the
/// dashboard.
class AuthController extends AsyncNotifier<AuthState>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _subscription;
  DateTime? _backgroundedAt;

  /// How long the app may sit in the background before the lock re-arms.
  static const Duration _lockGracePeriod = Duration(minutes: 2);

  @override
  Future<AuthState> build() async {
    final repository = ref.watch(authRepositoryProvider);

    _subscription = repository.watchAuthState().listen((next) {
      // Preserve the lock flag: the auth stream knows about sessions, not about
      // whether the user has passed the biometric gate.
      final locked = state.valueOrNull?.isLocked ?? false;
      state = AsyncData(next.copyWith(isLocked: locked && next.isAuthenticated));
    });

    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(_subscription?.cancel());
    });

    final restored = await repository.restoreSession();
    final restoredState = restored.valueOrNull ?? const AuthState();

    // If app lock is on, a restored session starts locked.
    final lockEnabled = ref.read(settingsProvider).biometricLock;
    return restoredState.copyWith(
      isLocked: lockEnabled && restoredState.isAuthenticated,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (!ref.read(settingsProvider).biometricLock) return;

    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      return;
    }
    if (lifecycle != AppLifecycleState.resumed) return;

    // A short grace period stops the lock firing when the user flips to their
    // authenticator app and straight back.
    final since = _backgroundedAt;
    if (since != null &&
        DateTime.now().difference(since) > _lockGracePeriod &&
        (state.valueOrNull?.isAuthenticated ?? false)) {
      lock();
    }
    _backgroundedAt = null;
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool showLoading = true,
  }) async {
    if (showLoading) state = const AsyncLoading<AuthState>().copyWithPrevious(state);
    try {
      await action();
    } on Failure catch (failure, stackTrace) {
      state = AsyncError<AuthState>(failure, stackTrace)
          .copyWithPrevious(state);
    }
  }

  Future<void> signInWithEmail(String email, String password) => _run(() async {
        final result = await ref
            .read(authRepositoryProvider)
            .signInWithEmail(email: email, password: password);
        state = result.fold(
          AsyncData<AuthState>.new,
          (failure) => AsyncError<AuthState>(failure, StackTrace.current),
        );
      });

  Future<void> signUp(String email, String password, String name) =>
      _run(() async {
        final result = await ref.read(authRepositoryProvider).signUpWithEmail(
              email: email,
              password: password,
              displayName: name,
            );
        state = result.fold(
          AsyncData<AuthState>.new,
          (failure) => AsyncError<AuthState>(failure, StackTrace.current),
        );
      });

  Future<void> signInWithGoogle() => _run(() async {
        final result = await ref.read(authRepositoryProvider).signInWithGoogle();
        state = result.fold(
          AsyncData<AuthState>.new,
          (failure) => AsyncError<AuthState>(failure, StackTrace.current),
        );
      });

  Future<void> signInWithApple() => _run(() async {
        final result = await ref.read(authRepositoryProvider).signInWithApple();
        state = result.fold(
          AsyncData<AuthState>.new,
          (failure) => AsyncError<AuthState>(failure, StackTrace.current),
        );
      });

  Future<void> continueLocally({String displayName = ''}) => _run(() async {
        final result = await ref
            .read(authRepositoryProvider)
            .continueLocally(displayName: displayName);
        state = result.fold(
          AsyncData<AuthState>.new,
          (failure) => AsyncError<AuthState>(failure, StackTrace.current),
        );
      });

  Future<void> signOut() => _run(() async {
        await ref.read(authRepositoryProvider).signOut();
        state = const AsyncData<AuthState>(AuthState());
      });

  void lock() {
    final current = state.valueOrNull;
    if (current == null || !current.isAuthenticated) return;
    ref.read(authRepositoryImplProvider).lock();
    state = AsyncData(current.copyWith(isLocked: true));
  }

  /// Prompts for biometrics and unlocks on success.
  Future<bool> unlock() async {
    final result =
        await ref.read(biometricServiceProvider).authenticate();
    final ok = result.valueOrNull ?? false;
    if (ok) {
      ref.read(authRepositoryImplProvider).unlock();
      final current = state.valueOrNull;
      if (current != null) state = AsyncData(current.copyWith(isLocked: false));
    }
    return ok;
  }

  Future<void> updateProfile(UserProfile profile) async {
    await ref.read(authRepositoryProvider).updateProfile(profile);
  }
}

final AsyncNotifierProvider<AuthController, AuthState> authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

/// The signed-in user, or null.
final Provider<UserProfile?> currentUserProvider = Provider<UserProfile?>(
  (ref) => ref.watch(authControllerProvider).valueOrNull?.user,
);
