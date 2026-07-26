import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/chat.dart' show CitationSource;
import '../../domain/entities/goal.dart';
import '../../domain/entities/task.dart';
import '../../domain/repositories/goal_repository.dart';
import '../local/app_database.dart';
import '../local/search_indexer.dart';
import '../mappers/mappers.dart';
import '../remote/sync_queue_writer.dart';

class GoalRepositoryImpl implements GoalRepository {
  GoalRepositoryImpl(this._db, this._sync) : _indexer = SearchIndexer(_db);

  final AppDatabase _db;
  final SyncQueueWriter _sync;
  final SearchIndexer _indexer;

  Future<List<Goal>> _hydrate(List<GoalRow> rows) async {
    if (rows.isEmpty) return const <Goal>[];
    final milestoneRows = await (_db.select(_db.milestones)
          ..where((t) => t.goalId.isIn(rows.map((r) => r.id).toList()))
          ..orderBy(<OrderClauseGenerator<$MilestonesTable>>[
            (t) => OrderingTerm.asc(t.position),
          ]))
        .get();

    final byGoal = <String, List<Milestone>>{};
    for (final row in milestoneRows) {
      byGoal.putIfAbsent(row.goalId, () => <Milestone>[]).add(row.toEntity());
    }
    return rows
        .map((row) =>
            row.toEntity(milestones: byGoal[row.id] ?? const <Milestone>[]))
        .toList();
  }

  @override
  Stream<List<Goal>> watchGoals({GoalStatus? status}) {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
            _db.goals,
            _db.milestones,
          },
        )
        .watch()
        .asyncMap((_) async {
          final query = _db.select(_db.goals)
            ..orderBy(<OrderClauseGenerator<$GoalsTable>>[
              (t) => OrderingTerm.asc(t.targetDate),
              (t) => OrderingTerm.desc(t.createdAt),
            ]);
          if (status != null) query.where((t) => t.status.equalsValue(status));
          return _hydrate(await query.get());
        });
  }

  @override
  Stream<Goal?> watchGoal(String id) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
          _db.goals,
          _db.milestones,
        },
      )
      .watch()
      .asyncMap((_) async {
        final row = await (_db.select(_db.goals)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (row == null) return null;
        return (await _hydrate(<GoalRow>[row])).first;
      });

  @override
  Future<Result<Goal?>> findById(String id) => Result.guard(() async {
        final row = await (_db.select(_db.goals)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (row == null) return null;
        return (await _hydrate(<GoalRow>[row])).first;
      });

  @override
  Future<Result<Goal>> upsert(Goal goal) => Result.guard(() async {
        await _db.transaction(() async {
          await _db.into(_db.goals).insertOnConflictUpdate(goal.toCompanion());
          for (final milestone in goal.milestones) {
            await _db
                .into(_db.milestones)
                .insertOnConflictUpdate(milestone.toCompanion());
          }
          await _indexer.index(
            source: CitationSource.goal,
            sourceId: goal.id,
            title: goal.title,
            body: '${goal.description} ${goal.category}',
            occurredAt: goal.targetDate ?? goal.createdAt,
          );
          await _sync.enqueue(
            entity: 'goals',
            entityId: goal.id,
            operation: SyncOperation.upsert,
            payload: goal.toJson(),
          );
        });
        return goal;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> delete(String id) => Result.guard(() async {
        await _db.transaction(() async {
          await (_db.delete(_db.goals)..where((t) => t.id.equals(id))).go();
          await _indexer.remove(CitationSource.goal, id);
          await _sync.enqueue(
            entity: 'goals',
            entityId: id,
            operation: SyncOperation.delete,
            payload: const <String, dynamic>{},
          );
        });
      });

  @override
  Future<Result<Milestone>> upsertMilestone(Milestone milestone) =>
      Result.guard(() async {
        await _db
            .into(_db.milestones)
            .insertOnConflictUpdate(milestone.toCompanion());
        return milestone;
      });

  @override
  Future<Result<void>> deleteMilestone(String milestoneId) =>
      Result.guard(() async {
        await (_db.delete(_db.milestones)..where((t) => t.id.equals(milestoneId)))
            .go();
      });

  @override
  Future<Result<void>> toggleMilestone(
    String milestoneId, {
    required bool done,
  }) =>
      Result.guard(() async {
        await (_db.update(_db.milestones)..where((t) => t.id.equals(milestoneId)))
            .write(
          MilestonesCompanion(
            completedAt: Value<DateTime?>(done ? DateTime.now() : null),
          ),
        );

        // Completing the last milestone finishes the goal — the user should not
        // have to mark the same thing done twice.
        final milestone = await (_db.select(_db.milestones)
              ..where((t) => t.id.equals(milestoneId)))
            .getSingleOrNull();
        if (milestone == null || !done) return;

        final siblings = await (_db.select(_db.milestones)
              ..where((t) => t.goalId.equals(milestone.goalId)))
            .get();
        if (siblings.every((m) => m.completedAt != null)) {
          await (_db.update(_db.goals)
                ..where((t) => t.id.equals(milestone.goalId)))
              .write(
            GoalsCompanion(
              status: const Value(GoalStatus.achieved),
              achievedAt: Value(DateTime.now()),
            ),
          );
        }
      });

  @override
  Future<Result<void>> applyPlan(GoalPlan plan, {bool createTasks = true}) =>
      Result.guard(() async {
        await _db.transaction(() async {
          // The roadmap becomes milestones, appended after whatever exists so a
          // regenerated plan never wipes the user's own entries.
          final existing = await (_db.select(_db.milestones)
                ..where((t) => t.goalId.equals(plan.goalId)))
              .get();
          var position = existing.length;

          for (final step in plan.monthlyRoadmap) {
            await _db.into(_db.milestones).insert(
                  MilestonesCompanion.insert(
                    id: newId(),
                    goalId: plan.goalId,
                    title: step,
                    position: Value(position++),
                  ),
                );
          }

          if (!createTasks) return;
          for (final item in plan.dailyTasks) {
            await _db.into(_db.tasks).insert(
                  TasksCompanion.insert(
                    id: newId(),
                    title: item,
                    createdAt: DateTime.now(),
                    priority: TaskPriority.medium,
                    status: TaskStatus.backlog,
                    goalId: Value(plan.goalId),
                    aiReason: const Value('Generated from your goal plan'),
                  ),
                );
          }
        });
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<List<Goal>>> atRisk() => Result.guard(() async {
        final rows = await (_db.select(_db.goals)
              ..where((t) => t.status.equalsValue(GoalStatus.active)))
            .get();
        final goals = await _hydrate(rows);
        return goals.where((goal) => goal.isAtRisk || goal.isOverdue).toList();
      });
}
