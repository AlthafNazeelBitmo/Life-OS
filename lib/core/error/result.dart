import 'dart:async';

import 'package:flutter/foundation.dart';

import 'failures.dart';

/// Explicit success/failure channel used by every repository and service.
///
/// Throwing is reserved for programmer errors; anything the user could plausibly
/// hit (offline, denied permission, bad input) travels as an [Err] so callers
/// are forced to handle it.
@immutable
sealed class Result<T> {
  const Result();

  /// Runs [body] and traps any error into a [Failure].
  static Future<Result<T>> guard<T>(
    FutureOr<T> Function() body, {
    Failure Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      return Ok<T>(await body());
    } on Failure catch (failure) {
      return Err<T>(failure);
    } catch (error, stackTrace) {
      return Err<T>(
        onError?.call(error, stackTrace) ??
            UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  Failure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };

  T getOrElse(T Function() fallback) => valueOrNull ?? fallback();

  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) =>
      switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onErr(failure),
      };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(:final value) => Ok<R>(transform(value)),
        Err<T>(:final failure) => Err<R>(failure),
      };

  Future<Result<R>> flatMap<R>(
    FutureOr<Result<R>> Function(T value) transform,
  ) async =>
      switch (this) {
        Ok<T>(:final value) => await transform(value),
        Err<T>(:final failure) => Err<R>(failure),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ok<T> && other.value == value);

  @override
  int get hashCode => Object.hash(Ok, value);
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Err<T> && other.failure == failure);

  @override
  int get hashCode => Object.hash(Err, failure);
}
