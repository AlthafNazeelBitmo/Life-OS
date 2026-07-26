import 'package:flutter/foundation.dart';

/// A user-presentable description of something that went wrong.
///
/// Failures never cross the UI boundary as raw exceptions: repositories and
/// services catch platform errors and translate them here, so every screen can
/// render a consistent message and decide whether a retry makes sense.
@immutable
sealed class Failure implements Exception {
  const Failure(this.message, {this.cause, this.stackTrace});

  /// Short, human-readable sentence. Safe to show in the UI.
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  /// Whether offering the user a "try again" affordance makes sense.
  bool get isRetryable => switch (this) {
        NetworkFailure() => true,
        SyncFailure() => true,
        UnknownFailure() => true,
        AiFailure(:final retryable) => retryable,
        DatabaseFailure() => false,
        AuthFailure() => false,
        PermissionFailure() => false,
        ValidationFailure() => false,
        NotFoundFailure() => false,
      };

  @override
  String toString() => '$runtimeType($message)';
}

final class NetworkFailure extends Failure {
  const NetworkFailure({
    String message = 'No connection. Your changes are saved on this device.',
    super.cause,
  }) : super(message);
}

final class DatabaseFailure extends Failure {
  const DatabaseFailure({
    String message = 'Could not read or write local data.',
    super.cause,
    super.stackTrace,
  }) : super(message);
}

final class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.cause});
}

final class PermissionFailure extends Failure {
  const PermissionFailure(super.message, {this.permission, super.cause});

  /// Platform permission that was denied, e.g. `microphone`.
  final String? permission;
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.field});

  /// Form field the message belongs to, when the error is field-scoped.
  final String? field;
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure({String message = 'That item no longer exists.'})
      : super(message);
}

final class SyncFailure extends Failure {
  const SyncFailure(super.message, {super.cause});
}

/// Raised by the AI layer: transport problems, quota, or a response that could
/// not be grounded in the user's own data.
final class AiFailure extends Failure {
  const AiFailure(
    super.message, {
    this.provider,
    this.retryable = true,
    super.cause,
  });

  final String? provider;
  final bool retryable;
}

final class UnknownFailure extends Failure {
  const UnknownFailure({
    String message = 'Something went wrong.',
    super.cause,
    super.stackTrace,
  }) : super(message);
}
