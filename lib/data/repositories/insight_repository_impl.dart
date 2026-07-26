import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/insight.dart';
import '../../domain/repositories/insight_repository.dart';
import '../local/app_database.dart';
import '../mappers/mappers.dart';

class InsightRepositoryImpl implements InsightRepository {
  const InsightRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Insight>> watchInsights({bool includeDismissed = false}) {
    final query = _db.select(_db.insights)
      ..orderBy(<OrderClauseGenerator<$InsightsTable>>[
        (t) => OrderingTerm.desc(t.pinned),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    if (!includeDismissed) query.where((t) => t.dismissed.equals(false));
    return query.watch().map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Future<Result<List<Insight>>> forPeriod(DateTime start, DateTime end) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.insights)
              ..where((t) => t.createdAt.isBetweenValues(start, end)))
            .get();
        return rows.map((r) => r.toEntity()).toList();
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> saveAll(List<Insight> insights) =>
      Result.guard(() async {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(
            _db.insights,
            insights.map((i) => i.toCompanion()).toList(),
          );
        });
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> setPinned(String id, {required bool pinned}) =>
      Result.guard(() async {
        await (_db.update(_db.insights)..where((t) => t.id.equals(id)))
            .write(InsightsCompanion(pinned: Value(pinned)));
      });

  @override
  Future<Result<void>> dismiss(String id) => Result.guard(() async {
        await (_db.update(_db.insights)..where((t) => t.id.equals(id)))
            .write(const InsightsCompanion(dismissed: Value(true)));
      });

  @override
  Future<Result<PeriodReview?>> findReview(
    ReviewPeriod period,
    DateTime start,
  ) =>
      Result.guard(() async {
        final row = await (_db.select(_db.periodReviews)
              ..where((t) =>
                  t.period.equalsValue(period) &
                  t.periodStart.equals(start)))
            .getSingleOrNull();
        if (row == null) return null;

        final insightRows = await (_db.select(_db.insights)
              ..where((t) =>
                  t.periodStart.equals(row.periodStart) &
                  t.periodEnd.equals(row.periodEnd)))
            .get();
        return row.toEntity(
          insights: insightRows.map((r) => r.toEntity()).toList(),
        );
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> saveReview(PeriodReview review) =>
      Result.guard(() async {
        await _db.transaction(() async {
          await _db
              .into(_db.periodReviews)
              .insertOnConflictUpdate(review.toCompanion());
          if (review.insights.isNotEmpty) {
            await _db.batch((batch) {
              batch.insertAllOnConflictUpdate(
                _db.insights,
                review.insights.map((i) => i.toCompanion()).toList(),
              );
            });
          }
        });
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Stream<List<PeriodReview>> watchReviews(ReviewPeriod period) =>
      (_db.select(_db.periodReviews)
            ..where((t) => t.period.equalsValue(period))
            ..orderBy(<OrderClauseGenerator<$PeriodReviewsTable>>[
              (t) => OrderingTerm.desc(t.periodStart),
            ]))
          .watch()
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<LifeScore>> latestLifeScore() => Result.guard(() async {
        final row = await (_db.select(_db.lifeScores)
              ..orderBy(<OrderClauseGenerator<$LifeScoresTable>>[
                (t) => OrderingTerm.desc(t.dayKey),
              ])
              ..limit(1))
            .getSingleOrNull();
        return row?.toEntity() ?? LifeScore(computedAt: DateTime.now());
      });

  @override
  Future<Result<void>> saveLifeScore(LifeScore score) =>
      Result.guard(() async {
        await _db.into(_db.lifeScores).insertOnConflictUpdate(
              LifeScoresCompanion.insert(
                dayKey: Fmt.dayKey(score.computedAt),
                habits: score.habits,
                health: score.health,
                finances: score.finances,
                productivity: score.productivity,
                mood: score.mood,
                missingPillars: Value(score.missingPillars),
                computedAt: score.computedAt,
              ),
            );
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<List<LifeScore>>> lifeScoreHistory({int days = 90}) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.lifeScores)
              ..orderBy(<OrderClauseGenerator<$LifeScoresTable>>[
                (t) => OrderingTerm.desc(t.dayKey),
              ])
              ..limit(days))
            .get();
        return rows.reversed.map((r) => r.toEntity()).toList();
      });
}
