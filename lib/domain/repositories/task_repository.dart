import '../../core/error/result.dart';
import '../entities/task.dart';

abstract interface class TaskRepository {
  Stream<List<Task>> watchTasks({TaskStatus? status, String? goalId});

  /// Everything due today, overdue, or explicitly moved into Today.
  Stream<List<Task>> watchToday();

  Stream<List<Task>> watchSubtasks(String parentId);

  Future<Result<List<Task>>> all({bool includeDone = false});

  Future<Result<Task?>> findById(String id);

  Future<Result<Task>> upsert(Task task);

  Future<Result<void>> delete(String id);

  /// Marks done and, for recurring tasks, schedules the next occurrence.
  Future<Result<void>> complete(String id, {required bool done});

  /// Kanban drag-and-drop: moves a task and rewrites the order of its column.
  Future<Result<void>> reorder({
    required String taskId,
    required TaskStatus toStatus,
    required int toIndex,
  });

  /// Applies an assistant-produced ranking. Stores the reason on each task so
  /// the UI can explain the order rather than silently rearranging the list.
  Future<Result<void>> applyPriorities(Map<String, String> reasonByTaskId);

  Future<Result<int>> completedCount({
    required DateTime from,
    required DateTime to,
  });
}
