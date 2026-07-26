import '../../core/error/result.dart';
import '../entities/goal.dart';

abstract interface class GoalRepository {
  Stream<List<Goal>> watchGoals({GoalStatus? status});

  Stream<Goal?> watchGoal(String id);

  Future<Result<Goal?>> findById(String id);

  Future<Result<Goal>> upsert(Goal goal);

  Future<Result<void>> delete(String id);

  Future<Result<Milestone>> upsertMilestone(Milestone milestone);

  Future<Result<void>> deleteMilestone(String milestoneId);

  Future<Result<void>> toggleMilestone(String milestoneId, {required bool done});

  /// Persists an AI breakdown and, when [createTasks] is set, materialises the
  /// daily items as real tasks so the plan is actionable rather than advisory.
  Future<Result<void>> applyPlan(GoalPlan plan, {bool createTasks = true});

  Future<Result<List<Goal>>> atRisk();
}
