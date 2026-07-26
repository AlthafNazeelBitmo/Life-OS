import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/extensions/date_time_x.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/stats.dart';
import '../../domain/entities/health_metric.dart';
import '../../domain/entities/mood_entry.dart';
import '../../domain/repositories/mood_repository.dart';
import '../local/app_database.dart';
import '../mappers/mappers.dart';
import '../remote/sync_queue_writer.dart';

class MoodRepositoryImpl implements MoodRepository {
  const MoodRepositoryImpl(this._db, this._sync);

  final AppDatabase _db;
  final SyncQueueWriter _sync;

  @override
  Stream<List<MoodEntry>> watchRange(DateTime from, DateTime to) {
    final query = _db.select(_db.moodEntries)
      ..where((t) => t.recordedAt.isBetweenValues(from, to))
      ..orderBy(<OrderClauseGenerator<$MoodEntriesTable>>[
        (t) => OrderingTerm.asc(t.recordedAt),
      ]);
    return query.watch().map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<MoodEntry?> watchLatest() {
    final query = _db.select(_db.moodEntries)
      ..orderBy(<OrderClauseGenerator<$MoodEntriesTable>>[
        (t) => OrderingTerm.desc(t.recordedAt),
      ])
      ..limit(1);
    return query.watch().map((rows) => rows.isEmpty ? null : rows.first.toEntity());
  }

  @override
  Future<Result<List<MoodEntry>>> range(DateTime from, DateTime to) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.moodEntries)
              ..where((t) => t.recordedAt.isBetweenValues(from, to))
              ..orderBy(<OrderClauseGenerator<$MoodEntriesTable>>[
                (t) => OrderingTerm.asc(t.recordedAt),
              ]))
            .get();
        return rows.map((r) => r.toEntity()).toList();
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<MoodEntry>> upsert(MoodEntry entry) => Result.guard(() async {
        await _db.transaction(() async {
          await _db
              .into(_db.moodEntries)
              .insertOnConflictUpdate(entry.toCompanion());
          await _sync.enqueue(
            entity: 'mood_entries',
            entityId: entry.id,
            operation: SyncOperation.upsert,
            payload: entry.toJson(),
          );
        });
        return entry;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> delete(String id) => Result.guard(() async {
        await (_db.delete(_db.moodEntries)..where((t) => t.id.equals(id))).go();
        await _sync.enqueue(
          entity: 'mood_entries',
          entityId: id,
          operation: SyncOperation.delete,
          payload: const <String, dynamic>{},
        );
      });

  @override
  Future<Result<Map<String, double>>> dailyAverages(
    MoodDimension dimension, {
    required DateTime from,
    required DateTime to,
  }) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.moodEntries)
              ..where((t) => t.recordedAt.isBetweenValues(from, to)))
            .get();

        final buckets = <String, List<double>>{};
        for (final row in rows) {
          buckets
              .putIfAbsent(row.dayKey, () => <double>[])
              .add(row.toEntity().valueOf(dimension).toDouble());
        }
        return buckets.map((key, values) => MapEntry(key, Stats.mean(values)));
      });

  @override
  Future<Result<List<MoodCorrelation>>> correlations({
    int lookbackDays = 90,
  }) =>
      Result.guard(() async {
        final to = DateTime.now().endOfDay;
        final from = to.subtract(Duration(days: lookbackDays)).startOfDay;

        final moodRows = await (_db.select(_db.moodEntries)
              ..where((t) => t.recordedAt.isBetweenValues(from, to)))
            .get();
        if (moodRows.length < 8) return const <MoodCorrelation>[];

        // Average each dimension per day so a day with three check-ins does not
        // outvote a day with one.
        final moodByDay = <String, List<MoodEntry>>{};
        for (final row in moodRows) {
          moodByDay.putIfAbsent(row.dayKey, () => <MoodEntry>[]).add(
                row.toEntity(),
              );
        }

        final factors = await _dailyFactors(from, to);
        final results = <MoodCorrelation>[];

        for (final dimension in MoodDimension.values) {
          for (final entry in factors.entries) {
            final xs = <double>[];
            final ys = <double>[];
            for (final day in moodByDay.keys) {
              final value = entry.value[day];
              if (value == null) continue;
              xs.add(value);
              ys.add(
                Stats.mean(
                  moodByDay[day]!.map((m) => m.valueOf(dimension).toDouble()),
                ),
              );
            }
            if (xs.length < 8) continue;

            final r = Stats.pearson(xs, ys);
            if (r.abs() < 0.35) continue;

            results.add(
              MoodCorrelation(
                factor: entry.key,
                dimension: dimension,
                coefficient: r,
                sampleSize: xs.length,
                description: _describe(entry.key, dimension, r),
              ),
            );
          }
        }

        results.sort(
          (a, b) => b.coefficient.abs().compareTo(a.coefficient.abs()),
        );
        return results.take(12).toList();
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  /// Builds `factor → (dayKey → value)` for everything that might explain a
  /// mood: each habit's completion, key health metrics, and whether the user
  /// journalled that day.
  Future<Map<String, Map<String, double>>> _dailyFactors(
    DateTime from,
    DateTime to,
  ) async {
    final factors = <String, Map<String, double>>{};

    final habits = await (_db.select(_db.habits)
          ..where((t) => t.archivedAt.isNull()))
        .get();
    final logs = await (_db.select(_db.habitLogs)
          ..where((t) => t.recordedAt.isBetweenValues(from, to)))
        .get();

    final allDays = <String>{
      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
        Fmt.dayKey(d),
    };

    for (final habit in habits) {
      final done = logs
          .where((log) => log.habitId == habit.id && log.value > 0)
          .map((log) => log.dayKey)
          .toSet();
      if (done.length < 5) continue; // too rare to say anything about
      factors['habit:${habit.name}'] = <String, double>{
        for (final day in allDays) day: done.contains(day) ? 1 : 0,
      };
    }

    final healthRows = await (_db.select(_db.healthMetrics)
          ..where((t) => t.recordedAt.isBetweenValues(from, to))
          ..orderBy(<OrderClauseGenerator<$HealthMetricsTable>>[
            (t) => OrderingTerm.asc(t.recordedAt),
          ]))
        .get();
    for (final kind in <HealthKind>[
      HealthKind.sleep,
      HealthKind.exercise,
      HealthKind.steps,
      HealthKind.water,
      HealthKind.screenTime,
    ]) {
      final byDay = <String, double>{};
      for (final row in healthRows.where((r) => r.kind == kind)) {
        // Cumulative metrics (steps, water) add up over the day; point-in-time
        // ones (weight, resting HR) take the most recent reading.
        byDay[row.dayKey] = kind.cumulative
            ? (byDay[row.dayKey] ?? 0) + row.value
            : row.value;
      }
      if (byDay.length >= 8) factors[kind.label.toLowerCase()] = byDay;
    }

    final journalDays = (await (_db.select(_db.journalEntries)
              ..where((t) =>
                  t.createdAt.isBetweenValues(from, to) & t.deletedAt.isNull()))
            .get())
        .map((row) => row.dayKey)
        .toSet();
    if (journalDays.length >= 5) {
      factors['journalled'] = <String, double>{
        for (final day in allDays) day: journalDays.contains(day) ? 1 : 0,
      };
    }

    return factors;
  }

  String _describe(String factor, MoodDimension dimension, double r) {
    final direction = r > 0 ? 'higher' : 'lower';
    final label = dimension.label.toLowerCase();
    final subject = factor.startsWith('habit:')
        ? 'On days you do "${factor.substring(6)}"'
        : 'On days with more ${factor.replaceAll('habit:', '')}';
    return '$subject, your $label tends to be $direction.';
  }
}
