import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_profile.freezed.dart';
part 'user_profile.g.dart';

enum AuthMethod { email, google, apple, local }

@freezed
abstract class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String id,
    required DateTime createdAt,
    @Default('') String email,
    @Default('') String displayName,
    String? avatarUrl,
    @Default(AuthMethod.local) AuthMethod method,
    String? timezone,

    /// What the user said they want out of LifeOS during onboarding. Fed to the
    /// assistant as standing context.
    @Default(<String>[]) List<String> focusAreas,
  }) = _UserProfile;

  const UserProfile._();

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);

  /// True for the on-device account used when no backend is configured or the
  /// user declined to sign in. Everything works; nothing syncs.
  bool get isLocalOnly => method == AuthMethod.local;

  String get firstName =>
      displayName.trim().isEmpty ? 'there' : displayName.trim().split(' ').first;
}

/// The app's authentication state.
///
/// [isLocked] is separate from sign-in: a signed-in user behind the biometric
/// gate is authenticated but locked, and the router treats those differently.
@freezed
abstract class AuthState with _$AuthState {
  const factory AuthState({
    UserProfile? user,
    @Default(false) bool isLocked,
    String? accessToken,
    DateTime? expiresAt,
  }) = _AuthState;

  const AuthState._();

  factory AuthState.signedOut() => const AuthState();

  factory AuthState.fromJson(Map<String, dynamic> json) =>
      _$AuthStateFromJson(json);

  bool get isAuthenticated => user != null;

  /// A cached session stays usable offline; only a remote call will discover it
  /// has actually expired, and the refresh happens transparently then.
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
}
