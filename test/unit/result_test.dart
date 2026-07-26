import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/error/failures.dart';
import 'package:lifeos/core/error/result.dart';

void main() {
  group('Result', () {
    test('Ok carries its value and folds to the success branch', () {
      const result = Ok<int>(42);

      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.failureOrNull, isNull);
      expect(result.fold((value) => 'ok $value', (_) => 'err'), 'ok 42');
    });

    test('Err carries its failure and folds to the error branch', () {
      const failure = ValidationFailure('too short', field: 'password');
      const result = Err<int>(failure);

      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, failure);
      expect(result.getOrElse(() => 7), 7);
    });

    test('map transforms Ok and passes Err through untouched', () {
      expect(const Ok<int>(2).map((value) => value * 3).valueOrNull, 6);

      const failure = NotFoundFailure();
      final mapped = const Err<int>(failure).map((value) => value * 3);
      expect(mapped.failureOrNull, failure);
    });

    test('guard converts a thrown Failure into Err without wrapping it', () async {
      const failure = AuthFailure('nope');
      final result = await Result.guard<int>(() => throw failure);

      expect(result.failureOrNull, same(failure));
    });

    test('guard wraps an unexpected error as UnknownFailure', () async {
      final result = await Result.guard<int>(() => throw StateError('boom'));

      expect(result.failureOrNull, isA<UnknownFailure>());
      expect(result.failureOrNull!.cause, isA<StateError>());
    });

    test('guard uses the supplied translator when one is given', () async {
      final result = await Result.guard<int>(
        () => throw StateError('boom'),
        onError: (error, stack) => const DatabaseFailure(),
      );

      expect(result.failureOrNull, isA<DatabaseFailure>());
    });

    test('flatMap chains only on success', () async {
      final chained =
          await const Ok<int>(2).flatMap((value) => Ok<String>('v$value'));
      expect(chained.valueOrNull, 'v2');

      final shortCircuited = await const Err<int>(NotFoundFailure())
          .flatMap((value) => Ok<String>('unreachable'));
      expect(shortCircuited.isErr, isTrue);
    });
  });

  group('Failure.isRetryable', () {
    test('separates transient problems from permanent ones', () {
      expect(const NetworkFailure().isRetryable, isTrue);
      expect(const SyncFailure('x').isRetryable, isTrue);
      expect(const AiFailure('rate limited').isRetryable, isTrue);

      expect(const AiFailure('bad key', retryable: false).isRetryable, isFalse);
      expect(const ValidationFailure('bad input').isRetryable, isFalse);
      expect(const AuthFailure('denied').isRetryable, isFalse);
    });
  });
}
