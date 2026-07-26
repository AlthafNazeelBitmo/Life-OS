import 'package:freezed_annotation/freezed_annotation.dart';

import 'recurrence.dart';

part 'task.freezed.dart';
part 'task.g.dart';

enum TaskPriority {
  none('None', 0),
  low('Low', 1),
  medium('Medium', 2),
  high('High', 3),
  urgent('Urgent', 4);

  const TaskPriority(this.label, this.weight);

  final String label;
  final int weight;
}

/// Kanban columns double as task status — one concept, not two.
enum TaskStatus { backlog, today, inProgress, blocked, done }

@freezed
abstract class Task with _$Task {
  const factory Task({
    required String id,
    required String title,
    required DateTime createdAt,
    @Default('') String notes,

    /// Set for subtasks. Only one level of nesting is supported by design —
    /// deeper trees turn a task list into a project manager.
    String? parentId,
    @Default(TaskPriority.none) TaskPriority priority,
    @Default(TaskStatus.backlog) TaskStatus status,
    DateTime? dueAt,
    DateTime? remindAt,
    @Default(<String>[]) List<String> labels,
    Recurrence? recurrence,

    /// Position within its Kanban column.
    @Default(0) int orderIndex,
    String? goalId,
    String? calendarEventId,

    /// Minutes the user expects this to take; feeds day planning.
    int? estimateMinutes,
    DateTime? completedAt,

    /// Set when the assistant reordered the list, so the UI can say why.
    String? aiReason,
  }) = _Task;

  const Task._();

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);

  bool get isDone => status == TaskStatus.done || completedAt != null;

  bool get isOverdue =>
      !isDone && dueAt != null && dueAt!.isBefore(DateTime.now());

  bool get isSubtask => parentId != null;

  /// Ranking used when the assistant is off, and as the tie-breaker when it is
  /// on: urgency (how soon it is due) plus importance (priority weight).
  double get urgencyScore {
    final priorityPart = priority.weight * 2.0;
    final due = dueAt;
    if (due == null) return priorityPart;
    final hoursLeft = due.difference(DateTime.now()).inMinutes / 60;
    if (hoursLeft <= 0) return priorityPart + 12; // overdue outranks everything
    if (hoursLeft <= 24) return priorityPart + 8;
    if (hoursLeft <= 72) return priorityPart + 4;
    if (hoursLeft <= 168) return priorityPart + 2;
    return priorityPart;
  }
}

/// One block in an AI-generated day plan.
@freezed
abstract class PlannedBlock with _$PlannedBlock {
  const factory PlannedBlock({
    required String title,
    required DateTime start,
    required DateTime end,
    String? taskId,
    String? eventId,
    @Default('') String reason,
    @Default(false) bool isFocusBlock,
  }) = _PlannedBlock;

  const PlannedBlock._();

  factory PlannedBlock.fromJson(Map<String, dynamic> json) =>
      _$PlannedBlockFromJson(json);

  Duration get duration => end.difference(start);
}

@freezed
abstract class DayPlan with _$DayPlan {
  const factory DayPlan({
    required DateTime date,
    @Default(<PlannedBlock>[]) List<PlannedBlock> blocks,
    @Default(<String>[]) List<String> topPriorities,
    String? summary,

    /// What the plan deliberately leaves out, so the user is not surprised.
    @Default(<String>[]) List<String> deferred,
    DateTime? generatedAt,
  }) = _DayPlan;

  factory DayPlan.fromJson(Map<String, dynamic> json) =>
      _$DayPlanFromJson(json);
}
