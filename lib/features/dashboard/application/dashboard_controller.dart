import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/cache/key_value_store.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/calendar_event.dart';
import '../../../domain/entities/goal.dart';
import '../../../domain/entities/health_metric.dart';
import '../../../domain/entities/mood_entry.dart';
import '../../../domain/entities/task.dart';
import '../../../domain/repositories/habit_repository.dart';

/// Everything the dashboard renders, resolved in one pass.
@immutable
class DashboardData {
  const DashboardData({
    required this.date,
    this.mood,
    this.habits = const <HabitWithProgress>[],
    this.events = const <CalendarEvent>[],
    this.tasks = const <Task>[],
    this.goals = const <Goal>[],
    this.health = const DailyHealthSummary(dayKey: ''),
    this.spentTodayMinor = 0,
    this.journalStreak = 0,
    this.aiSummary,
  });

  final DateTime date;
  final MoodEntry? mood;
  final List<HabitWithProgress> habits;
  final List<CalendarEvent> events;
  final List<Task> tasks;
  final List<Goal> goals;
  final DailyHealthSummary health;
  final int spentTodayMinor;
  final int journalStreak;

  /// Null while the briefing is still being generated — the rest of the
  /// dashboard never waits on it.
  final String? aiSummary;

  double get habitCompletion {
    if (habits.isEmpty) return 0;
    return habits.where((h) => h.isComplete).length / habits.length;
  }

  String get greeting => switch (date.hour) {
        < 5 => 'Still up?',
        < 12 => 'Good morning',
        < 17 => 'Good afternoon',
        < 22 => 'Good evening',
        _ => 'Winding down',
      };
}

/// Composes the dashboard from every module.
///
/// Each source is a Drift stream, so the screen updates the moment anything
/// changes anywhere in the app — logging a habit from the voice assistant
/// repaints the ring here without a manual refresh.
class DashboardController extends AsyncNotifier<DashboardData> {
  @override
  Future<DashboardData> build() async {
    final now = ref.watch(clockProvider)();

    // Watching the stream providers below — rather than reading each repository
    // once — is what makes the dashboard live: any write anywhere in the app
    // pushes through Drift and rebuilds exactly this provider.
    final habits = await ref.watch(_todayHabitsProvider.future);
    final events = await ref.watch(_upcomingEventsProvider.future);
    final tasks = await ref.watch(_todayTasksProvider.future);
    final mood = await ref.watch(_latestMoodProvider.future);
    final health = await ref.watch(_todayHealthProvider.future);
    final goals = await ref.watch(_activeGoalsProvider.future);

    final spent = await ref.watch(financeRepositoryProvider).spentOn(now);
    final streak = await ref.watch(journalRepositoryProvider).currentStreak();

    return DashboardData(
      date: now,
      mood: mood,
      habits: habits,
      events: events,
      tasks: tasks.take(5).toList(),
      goals: goals
          .where((goal) => goal.status == GoalStatus.active)
          .take(3)
          .toList(),
      health: health,
      spentTodayMinor: spent.valueOrNull ?? 0,
      journalStreak: streak.valueOrNull ?? 0,
      aiSummary: _cachedBriefing(now),
    );
  }

  String? _cachedBriefing(DateTime now) {
    final cached = ref.read(keyValueStoreProvider).getJson(
          CacheKeys.dailyBriefing,
        );
    if (cached == null) return null;
    // A briefing from yesterday is worse than none — it describes a day that
    // already happened.
    final generatedAt = DateTime.tryParse(cached['at'] as String? ?? '');
    if (generatedAt == null || !generatedAt.isSameDay(now)) return null;
    return cached['text'] as String?;
  }

  /// Generates today's briefing. Called by the dashboard after first paint, so
  /// the screen is never blocked on a model round trip.
  Future<void> refreshBriefing({bool force = false}) async {
    final now = ref.read(clockProvider)();
    if (!force && _cachedBriefing(now) != null) return;

    final context = await ref.read(contextBuilderProvider).forRange(
          from: now.subtract(const Duration(days: 7)),
          to: now.endOfDay,
          maxChunks: 40,
        );
    final result = await ref.read(aiServiceProvider).dailyBriefing(context);

    await result.fold(
      (summary) async {
        await ref.read(keyValueStoreProvider).setJson(
          CacheKeys.dailyBriefing,
          <String, dynamic>{'at': now.toIso8601String(), 'text': summary},
        );
        final current = state.valueOrNull;
        if (current != null) {
          state = AsyncData(
            DashboardData(
              date: current.date,
              mood: current.mood,
              habits: current.habits,
              events: current.events,
              tasks: current.tasks,
              goals: current.goals,
              health: current.health,
              spentTodayMinor: current.spentTodayMinor,
              journalStreak: current.journalStreak,
              aiSummary: summary,
            ),
          );
        }
      },
      // A failed briefing is not worth an error state on the whole dashboard.
      (failure) async {},
    );
  }

  Future<void> toggleHabit(String habitId, {required bool done}) async {
    await ref
        .read(habitRepositoryProvider)
        .log(habitId, ref.read(clockProvider)(), amount: done ? 1 : 0);
  }

  Future<void> logWater() async {
    await ref.read(healthRepositoryProvider).increment(HealthKind.water, 1);
  }

  Future<void> completeTask(String taskId, {required bool done}) async {
    await ref.read(taskRepositoryProvider).complete(taskId, done: done);
  }
}

// Each slice is its own stream provider so a change in one module rebuilds the
// dashboard without re-querying the others.

final StreamProvider<List<HabitWithProgress>> _todayHabitsProvider =
    StreamProvider<List<HabitWithProgress>>(
  (ref) => ref
      .watch(habitRepositoryProvider)
      .watchForDay(ref.watch(clockProvider)()),
);

final StreamProvider<List<CalendarEvent>> _upcomingEventsProvider =
    StreamProvider<List<CalendarEvent>>(
  (ref) => ref.watch(calendarRepositoryProvider).watchUpcoming(limit: 4),
);

final StreamProvider<List<Task>> _todayTasksProvider =
    StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchToday(),
);

final StreamProvider<MoodEntry?> _latestMoodProvider =
    StreamProvider<MoodEntry?>(
  (ref) => ref.watch(moodRepositoryProvider).watchLatest(),
);

final StreamProvider<DailyHealthSummary> _todayHealthProvider =
    StreamProvider<DailyHealthSummary>(
  (ref) =>
      ref.watch(healthRepositoryProvider).watchDay(ref.watch(clockProvider)()),
);

final StreamProvider<List<Goal>> _activeGoalsProvider =
    StreamProvider<List<Goal>>(
  (ref) => ref.watch(goalRepositoryProvider).watchGoals(),
);

final AsyncNotifierProvider<DashboardController, DashboardData>
    dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardData>(
  DashboardController.new,
);
