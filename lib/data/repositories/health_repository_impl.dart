import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/stats.dart';
import '../../domain/entities/health_metric.dart';
import '../../domain/repositories/health_repository.dart';
import '../local/app_database.dart';
import '../mappers/mappers.dart';
import '../remote/sync_queue_writer.dart';

class HealthRepositoryImpl implements HealthRepository {
  const HealthRepositoryImpl(this._db, this._sync);

  final AppDatabase _db;
  final SyncQueueWriter _sync;

  /// Collapses a day's readings into one value per metric: cumulative metrics
  /// sum, point-in-time metrics take the latest reading.
  DailyHealthSummary _summarise(String dayKey, List<HealthMetricRow> rows) {
    final values = <HealthKind, double>{};
    final sorted = rows.toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    for (final row in sorted) {
      values[row.kind] = row.kind.cumulative
          ? (values[row.kind] ?? 0) + row.value
          : row.value;
    }
    return DailyHealthSummary(dayKey: dayKey, values: values);
  }

  @override
  Stream<DailyHealthSummary> watchDay(DateTime day) {
    final dayKey = Fmt.dayKey(day);
    return (_db.select(_db.healthMetrics)..where((t) => t.dayKey.equals(dayKey)))
        .watch()
        .map((rows) => _summarise(dayKey, rows));
  }

  @override
  Stream<List<HealthMetric>> watchKind(
    HealthKind kind, {
    required DateTime from,
    required DateTime to,
  }) =>
      (_db.select(_db.healthMetrics)
            ..where((t) =>
                t.kind.equalsValue(kind) & t.recordedAt.isBetweenValues(from, to))
            ..orderBy(<OrderClauseGenerator<$HealthMetricsTable>>[
              (t) => OrderingTerm.asc(t.recordedAt),
            ]))
          .watch()
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<HealthMetric>> record(HealthMetric metric) =>
      Result.guard(() async {
        await _db.transaction(() async {
          await _db
              .into(_db.healthMetrics)
              .insertOnConflictUpdate(metric.toCompanion());
          await _sync.enqueue(
            entity: 'health_metrics',
            entityId: metric.id,
            operation: SyncOperation.upsert,
            payload: metric.toJson(),
          );
        });
        return metric;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> increment(
    HealthKind kind,
    double delta, {
    DateTime? on,
  }) =>
      Result.guard(() async {
        final when = on ?? DateTime.now();
        final dayKey = Fmt.dayKey(when);

        if (kind.cumulative) {
          // Cumulative metrics append: each glass of water is its own reading,
          // which keeps the timeline of *when* it happened.
          await _db.into(_db.healthMetrics).insert(
                HealthMetricsCompanion.insert(
                  id: newId(),
                  kind: kind,
                  value: delta,
                  recordedAt: when,
                  dayKey: dayKey,
                ),
              );
          return;
        }

        // Point-in-time metrics replace the day's reading instead.
        final existing = await (_db.select(_db.healthMetrics)
              ..where((t) => t.kind.equalsValue(kind) & t.dayKey.equals(dayKey)))
            .getSingleOrNull();
        await _db.into(_db.healthMetrics).insertOnConflictUpdate(
              HealthMetricsCompanion.insert(
                id: existing?.id ?? newId(),
                kind: kind,
                value: (existing?.value ?? 0) + delta,
                recordedAt: when,
                dayKey: dayKey,
              ),
            );
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> delete(String id) => Result.guard(() async {
        await (_db.delete(_db.healthMetrics)..where((t) => t.id.equals(id))).go();
      });

  @override
  Future<Result<DailyHealthSummary>> summaryFor(DateTime day) =>
      Result.guard(() async {
        final dayKey = Fmt.dayKey(day);
        final rows = await (_db.select(_db.healthMetrics)
              ..where((t) => t.dayKey.equals(dayKey)))
            .get();
        return _summarise(dayKey, rows);
      });

  @override
  Future<Result<Map<String, double>>> series(
    HealthKind kind, {
    required DateTime from,
    required DateTime to,
  }) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.healthMetrics)
              ..where((t) =>
                  t.kind.equalsValue(kind) &
                  t.recordedAt.isBetweenValues(from, to))
              ..orderBy(<OrderClauseGenerator<$HealthMetricsTable>>[
                (t) => OrderingTerm.asc(t.recordedAt),
              ]))
            .get();

        final result = <String, double>{};
        for (final row in rows) {
          result[row.dayKey] = kind.cumulative
              ? (result[row.dayKey] ?? 0) + row.value
              : row.value;
        }
        return result;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<double?>> average(
    HealthKind kind, {
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await series(kind, from: from, to: to);
    return result.map(
      (values) => values.isEmpty ? null : Stats.mean(values.values),
    );
  }

  @override
  Future<Result<Map<HealthKind, double>>> targets() => Result.guard(() async {
        final rows = await _db.select(_db.healthTargets).get();
        return <HealthKind, double>{
          for (final kind in HealthKind.values)
            if (kind.defaultTarget > 0) kind: kind.defaultTarget,
          for (final row in rows) row.kind: row.target,
        };
      });

  @override
  Future<Result<void>> setTarget(HealthKind kind, double target) =>
      Result.guard(() async {
        await _db.into(_db.healthTargets).insertOnConflictUpdate(
              HealthTargetsCompanion.insert(kind: kind, target: target),
            );
      });
}
