import 'package:freezed_annotation/freezed_annotation.dart';

part 'goal.freezed.dart';
part 'goal.g.dart';

enum GoalHorizon { shortTerm, longTerm }

enum GoalStatus { active, paused, achieved, abandoned }

@freezed
abstract class Milestone with _$Milestone {
  const factory Milestone({
    required String id,
    required String goalId,
    required String title,
    required int position,
    DateTime? dueDate,
    DateTime? completedAt,
    @Default('') String notes,
  }) = _Milestone;

  const Milestone._();

  factory Milestone.fromJson(Map<String, dynamic> json) =>
      _$MilestoneFromJson(json);

  bool get isDone => completedAt != null;

  bool get isOverdue =>
      !isDone && dueDate != null && dueDate!.isBefore(DateTime.now());
}

@freezed
abstract class Goal with _$Goal {
  const factory Goal({
    required String id,
    required String title,
    required DateTime createdAt,
    @Default('') String description,
    @Default(GoalHorizon.shortTerm) GoalHorizon horizon,
    @Default(GoalStatus.active) GoalStatus status,
    @Default('') String category,
    @Default(0xFFF08C3A) int colorValue,
    DateTime? targetDate,

    /// Manual override, 0–1. When null, progress is derived from milestones.
    double? manualProgress,
    @Default(<Milestone>[]) List<Milestone> milestones,

    /// Habits that feed this goal — used to explain "why this habit matters".
    @Default(<String>[]) List<String> habitIds,
    DateTime? achievedAt,
  }) = _Goal;

  const Goal._();

  factory Goal.fromJson(Map<String, dynamic> json) => _$GoalFromJson(json);

  /// Milestone completion, unless the user pinned a manual figure.
  double get progress {
    if (manualProgress != null) return manualProgress!.clamp(0.0, 1.0);
    if (milestones.isEmpty) return status == GoalStatus.achieved ? 1 : 0;
    final done = milestones.where((m) => m.isDone).length;
    return done / milestones.length;
  }

  int? get daysRemaining => targetDate == null
      ? null
      : targetDate!.difference(DateTime.now()).inDays;

  bool get isOverdue =>
      status == GoalStatus.active &&
      targetDate != null &&
      targetDate!.isBefore(DateTime.now());

  /// True when the deadline is closer than the progress suggests it should be.
  bool get isAtRisk {
    final remaining = daysRemaining;
    if (remaining == null || remaining < 0 || status != GoalStatus.active) {
      return false;
    }
    final total = targetDate!.difference(createdAt).inDays;
    if (total <= 0) return false;
    final elapsedFraction = (total - remaining) / total;
    return elapsedFraction - progress > 0.25;
  }

  Milestone? get nextMilestone {
    final pending = milestones.where((m) => !m.isDone).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return pending.isEmpty ? null : pending.first;
  }
}

/// AI breakdown of a goal into an actionable plan.
@freezed
abstract class GoalPlan with _$GoalPlan {
  const factory GoalPlan({
    required String goalId,
    @Default(<String>[]) List<String> dailyTasks,
    @Default(<String>[]) List<String> weeklyPlan,
    @Default(<String>[]) List<String> monthlyRoadmap,
    @Default(<String>[]) List<String> suggestedHabits,
    String? rationale,
    DateTime? generatedAt,
  }) = _GoalPlan;

  factory GoalPlan.fromJson(Map<String, dynamic> json) =>
      _$GoalPlanFromJson(json);
}
