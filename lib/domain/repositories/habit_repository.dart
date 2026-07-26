import '../../core/error/result.dart';
import '../entities/habit.dart';

abstract interface class HabitRepository {
  Stream<List<Habit>> watchHabits({bool includeArchived = false});

  /// Habits due on [date] paired with what has been logged so far.
  Stream<List<HabitWithProgress>> watchForDay(DateTime date);

  Stream<Habit?> watchHabit(String id);

  Future<Result<Habit>> upsert(Habit habit);

  Future<Result<void>> archive(String id);

  Future<Result<void>> delete(String id);

  /// Records progress. For binary habits [amount] is 1; passing 0 clears the
  /// day, which is how un-checking works.
  Future<Result<void>> log(String habitId, DateTime day, {int amount = 1});

  Future<Result<List<HabitLog>>> logsFor(
    String habitId, {
    required DateTime from,
    required DateTime to,
  });

  Future<Result<HabitStats>> stats(String habitId, {int lookbackDays = 365});

  /// Completion fraction across all active habits for a day — the dashboard
  /// ring.
  Future<Result<double>> dayCompletion(DateTime day);
}

/// A habit joined with today's logged amount.
class HabitWithProgress {
  const HabitWithProgress({
    required this.habit,
    required this.loggedAmount,
    required this.streak,
  });

  final Habit habit;
  final int loggedAmount;
  final int streak;

  bool get isComplete => loggedAmount >= habit.target;

  double get progress =>
      habit.target == 0 ? 0 : (loggedAmount / habit.target).clamp(0.0, 1.0);
}
