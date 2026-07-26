import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/result.dart';
import '../../core/extensions/date_time_x.dart';
import '../../core/utils/stats.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/entities/health_metric.dart';
import '../../domain/entities/insight.dart';
import '../../domain/entities/mood_entry.dart';

/// Computes the 0–100 life score.
///
/// Three principles keep the number honest:
///  * a pillar with too little data is reported as *untracked*, not as zero —
///    otherwise the score punishes people for not using every module;
///  * each pillar is scored against the user's own targets, not a population;
///  * the maths is entirely on-device, so the score is identical whether or not
///    an AI provider is configured.
class LifeScoreService {
  const LifeScoreService(this._ref);

  final Ref _ref;

  static const int _windowDays = 14;

  Future<Result<LifeScore>> compute() => Result.guard(() async {
        final now = DateTime.now();
        final from = now.subtract(const Duration(days: _windowDays)).startOfDay;
        final missing = <String>[];

        final habits = await _habitsPillar(from, now, missing);
        final health = await _healthPillar(from, now, missing);
        final finances = await _financesPillar(now, missing);
        final productivity = await _productivityPillar(from, now, missing);
        final mood = await _moodPillar(from, now, missing);

        final score = LifeScore(
          computedAt: now,
          habits: habits,
          health: health,
          finances: finances,
          productivity: productivity,
          mood: mood,
          missingPillars: missing,
        );

        await _ref.read(insightRepositoryProvider).saveLifeScore(score);
        return score;
      });

  Future<int> _habitsPillar(
    DateTime from,
    DateTime to,
    List<String> missing,
  ) async {
    final repository = _ref.read(habitRepositoryProvider);
    final habits = await repository.watchHabits().first;
    if (habits.isEmpty) {
      missing.add('Habits');
      return 0;
    }

    final scores = <double>[];
    for (final habit in habits) {
      final stats = await repository.stats(habit.id, lookbackDays: _windowDays);
      final value = stats.valueOrNull;
      if (value != null) scores.add(value.score.toDouble());
    }
    return scores.isEmpty ? 0 : Stats.mean(scores).round();
  }

  Future<int> _healthPillar(
    DateTime from,
    DateTime to,
    List<String> missing,
  ) async {
    final repository = _ref.read(healthRepositoryProvider);
    final targets = (await repository.targets()).valueOrNull ??
        const <HealthKind, double>{};

    final ratios = <double>[];
    for (final kind in <HealthKind>[
      HealthKind.sleep,
      HealthKind.exercise,
      HealthKind.steps,
      HealthKind.water,
    ]) {
      final average = (await repository.average(kind, from: from, to: to))
          .valueOrNull;
      final target = targets[kind] ?? kind.defaultTarget;
      if (average == null || target <= 0) continue;
      // Capped at 1: doing double your step goal does not offset no sleep.
      ratios.add((average / target).clamp(0.0, 1.0));
    }

    if (ratios.isEmpty) {
      missing.add('Health');
      return 0;
    }
    return (Stats.mean(ratios) * 100).round();
  }

  Future<int> _financesPillar(DateTime now, List<String> missing) async {
    final repository = _ref.read(financeRepositoryProvider);
    final month = now.startOfMonth;
    final transactions = (await repository.range(month, now)).valueOrNull ?? [];
    if (transactions.isEmpty) {
      missing.add('Finances');
      return 0;
    }

    final income = transactions
        .where((t) => t.signedMinor > 0)
        .fold<int>(0, (sum, t) => sum + t.signedMinor);
    final spent = transactions
        .where((t) => t.signedMinor < 0)
        .fold<int>(0, (sum, t) => sum - t.signedMinor);

    // Two signals: are you inside your budgets, and are you keeping anything?
    final budgets = await repository.watchBudgets(month).first;
    final budgetScore = budgets.isEmpty
        ? null
        : budgets
                .map((b) => b.isOver ? 0.0 : (1 - b.fraction).clamp(0.0, 1.0))
                .reduce((a, b) => a + b) /
            budgets.length;

    final savingsRate = income == 0
        ? null
        : ((income - spent) / income).clamp(0.0, 1.0).toDouble();

    final parts = <double>[
      if (budgetScore != null) budgetScore,
      // A 20% savings rate reads as a full mark rather than requiring 100%.
      if (savingsRate != null) (savingsRate / 0.2).clamp(0.0, 1.0),
    ];
    if (parts.isEmpty) {
      missing.add('Finances');
      return 0;
    }
    return (Stats.mean(parts) * 100).round();
  }

  Future<int> _productivityPillar(
    DateTime from,
    DateTime to,
    List<String> missing,
  ) async {
    final repository = _ref.read(taskRepositoryProvider);
    final completed =
        (await repository.completedCount(from: from, to: to)).valueOrNull ?? 0;
    final open = (await repository.all()).valueOrNull ?? [];
    final overdue = open.where((task) => task.isOverdue).length;

    if (completed == 0 && open.isEmpty) {
      missing.add('Productivity');
      return 0;
    }

    // Throughput of roughly one task a day reads as a full mark; overdue items
    // subtract, because a growing backlog is the thing that actually hurts.
    final throughput = (completed / _windowDays).clamp(0.0, 1.0);
    final drag = (overdue / 10).clamp(0.0, 0.5);
    return ((throughput - drag).clamp(0.0, 1.0) * 100).round();
  }

  Future<int> _moodPillar(
    DateTime from,
    DateTime to,
    List<String> missing,
  ) async {
    final entries =
        (await _ref.read(moodRepositoryProvider).range(from, to)).valueOrNull ??
            const <MoodEntry>[];
    if (entries.length < 3) {
      missing.add('Mood');
      return 0;
    }
    return (Stats.mean(entries.map((entry) => entry.overall)) * 100).round();
  }
}

final Provider<LifeScoreService> lifeScoreServiceProvider =
    Provider<LifeScoreService>(LifeScoreService.new);

/// Recomputed on demand — the dashboard watches this.
final FutureProvider<LifeScore> lifeScoreProvider =
    FutureProvider<LifeScore>((ref) async {
  final result = await ref.watch(lifeScoreServiceProvider).compute();
  return result.fold((score) => score, (failure) => throw failure);
});
