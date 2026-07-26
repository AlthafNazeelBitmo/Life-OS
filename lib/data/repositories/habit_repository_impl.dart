import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/extensions/date_time_x.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/habit.dart';
import '../../domain/repositories/habit_repository.dart';
import '../local/app_database.dart';
import '../mappers/mappers.dart';
import '../remote/sync_queue_writer.dart';

class HabitRepositoryImpl implements HabitRepository {
  const HabitRepositoryImpl(this._db, this._sync);

  final AppDatabase _db;
  final SyncQueueWriter _sync;

  @override
  Stream<List<Habit>> watchHabits({bool includeArchived = false}) {
    final query = _db.select(_db.habits)
      ..orderBy(<OrderClauseGenerator<$HabitsTable>>[
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    if (!includeArchived) query.where((t) => t.archivedAt.isNull());
    return query.watch().map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<HabitWithProgress>> watchForDay(DateTime date) {
    final dayKey = Fmt.dayKey(date);

    // Both tables feed each row, so the stream must re-emit when either
    // changes — `readsFrom` is what registers habit_logs as a dependency.
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
            _db.habits,
            _db.habitLogs,
          },
        )
        .watch()
        .asyncMap((_) async {
          final habitRows = await _db.select(_db.habits).get();
          final logs = await (_db.select(_db.habitLogs)
                ..where((t) => t.dayKey.equals(dayKey)))
              .get();
          final byHabit = <String, int>{
            for (final log in logs) log.habitId: log.value,
          };

          final result = <HabitWithProgress>[];
          for (final row in habitRows) {
            final habit = row.toEntity();
            if (habit.isArchived || !habit.isScheduledOn(date)) continue;
            result.add(
              HabitWithProgress(
                habit: habit,
                loggedAmount: byHabit[habit.id] ?? 0,
                streak: await _streakFor(habit, upTo: date),
              ),
            );
          }
          return result;
        });
  }

  @override
  Stream<Habit?> watchHabit(String id) =>
      (_db.select(_db.habits)..where((t) => t.id.equals(id)))
          .watchSingleOrNull()
          .map((row) => row?.toEntity());

  @override
  Future<Result<Habit>> upsert(Habit habit) => Result.guard(() async {
        await _db.transaction(() async {
          await _db.into(_db.habits).insertOnConflictUpdate(habit.toCompanion());
          await _sync.enqueue(
            entity: 'habits',
            entityId: habit.id,
            operation: SyncOperation.upsert,
            payload: habit.toJson(),
          );
        });
        return habit;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> archive(String id) => Result.guard(() async {
        await (_db.update(_db.habits)..where((t) => t.id.equals(id)))
            .write(HabitsCompanion(archivedAt: Value(DateTime.now())));
      });

  @override
  Future<Result<void>> delete(String id) => Result.guard(() async {
        // Logs cascade with the habit; the history goes with it by design.
        await (_db.delete(_db.habits)..where((t) => t.id.equals(id))).go();
        await _sync.enqueue(
          entity: 'habits',
          entityId: id,
          operation: SyncOperation.delete,
          payload: const <String, dynamic>{},
        );
      });

  @override
  Future<Result<void>> log(String habitId, DateTime day, {int amount = 1}) =>
      Result.guard(() async {
        final dayKey = Fmt.dayKey(day);
        await _db.transaction(() async {
          final existing = await (_db.select(_db.habitLogs)
                ..where((t) => t.habitId.equals(habitId) & t.dayKey.equals(dayKey)))
              .getSingleOrNull();

          if (amount <= 0) {
            // Un-checking removes the row rather than storing a zero, so
            // "logged nothing" and "never logged" stay the same thing.
            if (existing != null) {
              await (_db.delete(_db.habitLogs)
                    ..where((t) => t.id.equals(existing.id)))
                  .go();
            }
            return;
          }

          await _db.into(_db.habitLogs).insertOnConflictUpdate(
                HabitLogsCompanion.insert(
                  id: existing?.id ?? newId(),
                  habitId: habitId,
                  dayKey: dayKey,
                  recordedAt: DateTime.now(),
                  value: Value(amount),
                ),
              );
        });
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<List<HabitLog>>> logsFor(
    String habitId, {
    required DateTime from,
    required DateTime to,
  }) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.habitLogs)
              ..where(
                (t) =>
                    t.habitId.equals(habitId) &
                    t.dayKey.isBetweenValues(Fmt.dayKey(from), Fmt.dayKey(to)),
              ))
            .get();
        return rows.map((r) => r.toEntity()).toList();
      });

  @override
  Future<Result<HabitStats>> stats(String habitId, {int lookbackDays = 365}) =>
      Result.guard(() async {
        final habitRow = await (_db.select(_db.habits)
              ..where((t) => t.id.equals(habitId)))
            .getSingleOrNull();
        if (habitRow == null) {
          throw const NotFoundFailure(message: 'That habit no longer exists.');
        }
        final habit = habitRow.toEntity();

        final to = DateTime.now().startOfDay;
        final from = to.subtract(Duration(days: lookbackDays));
        final logs = await (_db.select(_db.habitLogs)
              ..where(
                (t) =>
                    t.habitId.equals(habitId) &
                    t.dayKey.isBiggerOrEqualValue(Fmt.dayKey(from)),
              ))
            .get();

        final heatmap = <String, int>{
          for (final log in logs) log.dayKey: log.value,
        };
        final completed = <String>{
          for (final log in logs)
            if (log.value >= habit.target) log.dayKey,
        };

        // Only days the habit was actually scheduled count against the rate —
        // a weekly habit should not look 86% incomplete.
        final scheduledDays = <String>[];
        final start = habit.createdAt.startOfDay.isAfter(from)
            ? habit.createdAt.startOfDay
            : from;
        for (final day in daysInRange(start, to)) {
          if (habit.isScheduledOn(day)) scheduledDays.add(Fmt.dayKey(day));
        }

        final hits = scheduledDays.where(completed.contains).length;
        final completionRate =
            scheduledDays.isEmpty ? 0.0 : hits / scheduledDays.length;

        final current = await _streakFor(habit, upTo: to);
        final longest = _longestStreak(habit, completed, from: start, to: to);

        // Consistency dominates, with recency and streak as modifiers: a habit
        // done every day for a month should not be outranked by one with a
        // lucky five-day run.
        final recencyBonus = completed.contains(Fmt.dayKey(to)) ||
                completed.contains(Fmt.dayKey(to.subtract(const Duration(days: 1))))
            ? 10
            : 0;
        final streakBonus = (current * 1.5).clamp(0, 20).round();
        final score =
            (completionRate * 70 + recencyBonus + streakBonus).clamp(0, 100).round();

        return HabitStats(
          habitId: habitId,
          currentStreak: current,
          longestStreak: longest,
          completionRate: completionRate,
          totalCompletions: completed.length,
          score: score,
          heatmap: heatmap,
        );
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<double>> dayCompletion(DateTime day) => Result.guard(() async {
        final habits = (await (_db.select(_db.habits)
                  ..where((t) => t.archivedAt.isNull()))
                .get())
            .map((r) => r.toEntity())
            .where((h) => h.isScheduledOn(day))
            .toList();
        if (habits.isEmpty) return 0.0;

        final logs = await (_db.select(_db.habitLogs)
              ..where((t) => t.dayKey.equals(Fmt.dayKey(day))))
            .get();
        final byHabit = <String, int>{
          for (final log in logs) log.habitId: log.value,
        };

        final done = habits
            .where((habit) => (byHabit[habit.id] ?? 0) >= habit.target)
            .length;
        return done / habits.length;
      });

  /// Counts back from [upTo] over the days this habit was scheduled. A missed
  /// *scheduled* day breaks the streak; a day it was never due does not.
  Future<int> _streakFor(Habit habit, {required DateTime upTo}) async {
    final logs = await (_db.select(_db.habitLogs)
          ..where((t) => t.habitId.equals(habit.id)))
        .get();
    final completed = <String>{
      for (final log in logs)
        if (log.value >= habit.target) log.dayKey,
    };
    if (completed.isEmpty) return 0;

    var cursor = upTo.startOfDay;
    // Today not being done yet must not zero out an otherwise live streak.
    if (habit.isScheduledOn(cursor) && !completed.contains(Fmt.dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }

    var streak = 0;
    var guard = 0;
    while (guard++ < 3650) {
      if (cursor.isBefore(habit.createdAt.startOfDay)) break;
      if (habit.isScheduledOn(cursor)) {
        if (!completed.contains(Fmt.dayKey(cursor))) break;
        streak++;
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int _longestStreak(
    Habit habit,
    Set<String> completed, {
    required DateTime from,
    required DateTime to,
  }) {
    var longest = 0;
    var running = 0;
    for (final day in daysInRange(from, to)) {
      if (!habit.isScheduledOn(day)) continue;
      if (completed.contains(Fmt.dayKey(day))) {
        running++;
        if (running > longest) longest = running;
      } else {
        running = 0;
      }
    }
    return longest;
  }
}
