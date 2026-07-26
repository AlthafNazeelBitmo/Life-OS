import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/extensions/date_time_x.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/chat.dart' show CitationSource;
import '../../domain/entities/task.dart';
import '../../domain/repositories/task_repository.dart';
import '../local/app_database.dart';
import '../local/search_indexer.dart';
import '../mappers/mappers.dart';
import '../remote/sync_queue_writer.dart';

class TaskRepositoryImpl implements TaskRepository {
  TaskRepositoryImpl(this._db, this._sync) : _indexer = SearchIndexer(_db);

  final AppDatabase _db;
  final SyncQueueWriter _sync;
  final SearchIndexer _indexer;

  @override
  Stream<List<Task>> watchTasks({TaskStatus? status, String? goalId}) {
    final query = _db.select(_db.tasks)
      ..orderBy(<OrderClauseGenerator<$TasksTable>>[
        (t) => OrderingTerm.asc(t.orderIndex),
        (t) => OrderingTerm.asc(t.dueAt),
      ]);
    if (status != null) query.where((t) => t.status.equalsValue(status));
    if (goalId != null) query.where((t) => t.goalId.equals(goalId));
    return query.watch().map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Task>> watchToday() {
    final endOfToday = DateTime.now().endOfDay;
    final query = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.completedAt.isNull() &
            (t.status.equalsValue(TaskStatus.today) |
                t.status.equalsValue(TaskStatus.inProgress) |
                t.dueAt.isSmallerOrEqualValue(endOfToday)),
      )
      ..orderBy(<OrderClauseGenerator<$TasksTable>>[
        (t) => OrderingTerm.asc(t.orderIndex),
      ]);
    return query.watch().map((rows) {
      final tasks = rows.map((r) => r.toEntity()).toList()
        // Secondary sort in Dart: urgency mixes a due date with a priority
        // weight, which SQL cannot express without a stored column that would
        // go stale every hour.
        ..sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));
      return tasks;
    });
  }

  @override
  Stream<List<Task>> watchSubtasks(String parentId) =>
      (_db.select(_db.tasks)
            ..where((t) => t.parentId.equals(parentId))
            ..orderBy(<OrderClauseGenerator<$TasksTable>>[
              (t) => OrderingTerm.asc(t.orderIndex),
            ]))
          .watch()
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<List<Task>>> all({bool includeDone = false}) =>
      Result.guard(() async {
        final query = _db.select(_db.tasks);
        if (!includeDone) query.where((t) => t.completedAt.isNull());
        final rows = await query.get();
        return rows.map((r) => r.toEntity()).toList();
      });

  @override
  Future<Result<Task?>> findById(String id) => Result.guard(() async {
        final row = await (_db.select(_db.tasks)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toEntity();
      });

  @override
  Future<Result<Task>> upsert(Task task) => Result.guard(() async {
        await _db.transaction(() async {
          await _db.into(_db.tasks).insertOnConflictUpdate(task.toCompanion());
          await _indexer.index(
            source: CitationSource.task,
            sourceId: task.id,
            title: task.title,
            body: '${task.notes} ${task.labels.join(' ')}',
            occurredAt: task.dueAt ?? task.createdAt,
          );
          await _sync.enqueue(
            entity: 'tasks',
            entityId: task.id,
            operation: SyncOperation.upsert,
            payload: task.toJson(),
          );
        });
        return task;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> delete(String id) => Result.guard(() async {
        await _db.transaction(() async {
          // Subtasks have no meaning without their parent.
          await (_db.delete(_db.tasks)
                ..where((t) => t.id.equals(id) | t.parentId.equals(id)))
              .go();
          await _indexer.remove(CitationSource.task, id);
          await _sync.enqueue(
            entity: 'tasks',
            entityId: id,
            operation: SyncOperation.delete,
            payload: const <String, dynamic>{},
          );
        });
      });

  @override
  Future<Result<void>> complete(String id, {required bool done}) =>
      Result.guard(() async {
        final row = await (_db.select(_db.tasks)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (row == null) throw const NotFoundFailure();
        final task = row.toEntity();

        await _db.transaction(() async {
          await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
            TasksCompanion(
              status: Value(done ? TaskStatus.done : TaskStatus.today),
              completedAt: Value<DateTime?>(done ? DateTime.now() : null),
            ),
          );

          // Completing a repeating task spawns the next one immediately, so the
          // series survives even if the app is never opened again until then.
          final rule = task.recurrence;
          if (done && rule != null) {
            final anchor = task.dueAt ?? task.createdAt;
            final next = rule.nextAfter(anchor, anchor: anchor);
            if (next != null) {
              await _db.into(_db.tasks).insert(
                    task
                        .copyWith(
                          id: newId(),
                          status: TaskStatus.backlog,
                          completedAt: null,
                          createdAt: DateTime.now(),
                          dueAt: next,
                          remindAt: task.remindAt == null
                              ? null
                              : next.subtract(
                                  anchor.difference(task.remindAt!),
                                ),
                        )
                        .toCompanion(),
                  );
            }
          }
        });
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> reorder({
    required String taskId,
    required TaskStatus toStatus,
    required int toIndex,
  }) =>
      Result.guard(() async {
        await _db.transaction(() async {
          final column = await (_db.select(_db.tasks)
                ..where((t) => t.status.equalsValue(toStatus))
                ..orderBy(<OrderClauseGenerator<$TasksTable>>[
                  (t) => OrderingTerm.asc(t.orderIndex),
                ]))
              .get();

          final ids = column.map((row) => row.id).toList()..remove(taskId);
          ids.insert(toIndex.clamp(0, ids.length), taskId);

          for (var i = 0; i < ids.length; i++) {
            await (_db.update(_db.tasks)..where((t) => t.id.equals(ids[i])))
                .write(
              TasksCompanion(
                orderIndex: Value(i),
                status: Value(toStatus),
                completedAt: toStatus == TaskStatus.done
                    ? Value(DateTime.now())
                    : const Value<DateTime?>(null),
              ),
            );
          }
        });
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> applyPriorities(Map<String, String> reasonByTaskId) =>
      Result.guard(() async {
        await _db.transaction(() async {
          var index = 0;
          for (final entry in reasonByTaskId.entries) {
            await (_db.update(_db.tasks)..where((t) => t.id.equals(entry.key)))
                .write(
              TasksCompanion(
                orderIndex: Value(index++),
                aiReason: Value(entry.value),
              ),
            );
          }
        });
      });

  @override
  Future<Result<int>> completedCount({
    required DateTime from,
    required DateTime to,
  }) =>
      Result.guard(() async {
        final row = await _db.customSelect(
          'SELECT COUNT(*) AS c FROM tasks '
          'WHERE completed_at IS NOT NULL AND completed_at BETWEEN ? AND ?',
          variables: <Variable<Object>>[
            Variable.withDateTime(from),
            Variable.withDateTime(to),
          ],
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{_db.tasks},
        ).getSingle();
        return row.read<int>('c');
      });
}
