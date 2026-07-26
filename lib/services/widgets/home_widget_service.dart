import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/error/result.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/repository_providers.dart';
import '../analytics/life_score_service.dart';

/// Publishes data to the Android and iOS home-screen widgets.
///
/// Flutter cannot draw the widgets themselves — those are native views — so the
/// contract is a set of shared-preferences keys the native side reads. Keeping
/// every key in one place here is what stops the two platforms drifting apart.
class HomeWidgetService {
  const HomeWidgetService(this._ref);

  final Ref _ref;

  /// Must match the App Group in the iOS extension's entitlements.
  static const String iosAppGroupId = 'group.com.lifeos.widgets';
  static const String androidProviderName = 'LifeOsWidgetProvider';
  static const String iosWidgetName = 'LifeOsWidget';

  static const String keyTodayTasks = 'today_tasks';
  static const String keyTaskCount = 'task_count';
  static const String keyHabits = 'habits';
  static const String keyHabitProgress = 'habit_progress';
  static const String keyMood = 'mood';
  static const String keyNextEvent = 'next_event';
  static const String keySpentToday = 'spent_today';
  static const String keySummary = 'ai_summary';
  static const String keyLifeScore = 'life_score';
  static const String keyUpdatedAt = 'updated_at';

  Future<void> initialize() async {
    try {
      await HomeWidget.setAppGroupId(iosAppGroupId);
    } catch (error) {
      // No widget extension installed is a perfectly normal state.
      AppLogger.info('widgets', 'Home widget unavailable ($error)');
    }
  }

  /// Refreshes every widget surface. Called after significant writes and on
  /// app pause — cheap enough that being liberal about it costs nothing.
  Future<Result<void>> refresh() => Result.guard(() async {
        final now = DateTime.now();

        final tasks = await _ref.read(taskRepositoryProvider).watchToday().first;
        final habits =
            await _ref.read(habitRepositoryProvider).watchForDay(now).first;
        final mood = await _ref.read(moodRepositoryProvider).watchLatest().first;
        final events = await _ref
            .read(calendarRepositoryProvider)
            .watchUpcoming(limit: 1)
            .first;
        final spent =
            (await _ref.read(financeRepositoryProvider).spentOn(now)).valueOrNull;
        final score = (await _ref.read(lifeScoreServiceProvider).compute())
            .valueOrNull;

        final doneHabits = habits.where((h) => h.isComplete).length;

        await Future.wait<void>(<Future<void>>[
          HomeWidget.saveWidgetData<String>(
            keyTodayTasks,
            jsonEncode(
              tasks
                  .take(4)
                  .map(
                    (task) => <String, Object?>{
                      'title': task.title,
                      'due': task.dueAt?.toIso8601String(),
                      'overdue': task.isOverdue,
                    },
                  )
                  .toList(),
            ),
          ),
          HomeWidget.saveWidgetData<int>(keyTaskCount, tasks.length),
          HomeWidget.saveWidgetData<String>(
            keyHabits,
            habits.take(5).map((h) => h.habit.emoji).join(' '),
          ),
          HomeWidget.saveWidgetData<String>(
            keyHabitProgress,
            habits.isEmpty ? '—' : '$doneHabits/${habits.length}',
          ),
          HomeWidget.saveWidgetData<String>(
            keyMood,
            mood == null ? '—' : '${mood.emoji} ${mood.label}',
          ),
          HomeWidget.saveWidgetData<String>(
            keyNextEvent,
            events.isEmpty
                ? 'Nothing scheduled'
                : '${Fmt.time(events.first.start)} · ${events.first.title}',
          ),
          HomeWidget.saveWidgetData<String>(
            keySpentToday,
            spent == null ? '—' : Fmt.money(spent),
          ),
          HomeWidget.saveWidgetData<int>(keyLifeScore, score?.total ?? 0),
          HomeWidget.saveWidgetData<String>(
            keyUpdatedAt,
            now.toIso8601String(),
          ),
        ]);

        await HomeWidget.updateWidget(
          androidName: androidProviderName,
          iOSName: iosWidgetName,
        );
      });

  /// Pushes the morning briefing text once it has been generated.
  Future<void> publishSummary(String summary) async {
    await HomeWidget.saveWidgetData<String>(keySummary, summary);
    await HomeWidget.updateWidget(
      androidName: androidProviderName,
      iOSName: iosWidgetName,
    );
  }
}

final Provider<HomeWidgetService> homeWidgetServiceProvider =
    Provider<HomeWidgetService>(HomeWidgetService.new);
