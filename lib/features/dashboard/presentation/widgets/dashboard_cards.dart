import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../ai/ai_providers.dart';
import '../../../../core/extensions/context_x.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/settings/settings_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/progress_ring.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/stat_tile.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../domain/entities/calendar_event.dart';
import '../../../../domain/entities/goal.dart';
import '../../../../domain/entities/health_metric.dart';
import '../../../../domain/entities/mood_entry.dart';
import '../../../../domain/entities/task.dart';
import '../../../../domain/repositories/habit_repository.dart';
import '../../../../services/analytics/life_score_service.dart';
import '../../application/dashboard_controller.dart';

/// The assistant's morning briefing.
///
/// Shows a skeleton rather than a spinner while it generates, and states
/// plainly when it came from on-device heuristics — the user should always know
/// whether a model was involved.
class BriefingCard extends ConsumerWidget {
  const BriefingCard({required this.summary, super.key});

  final String? summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLive = ref.watch(aiIsLiveProvider);

    return GlassCard(
      accent: AppColors.insights,
      semanticLabel: 'Today’s briefing',
      onTap: () => context.push(Routes.chat),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.auto_awesome_rounded, size: 18),
              Gap.w8,
              Text('Today', style: context.text.titleSmall),
              const Spacer(),
              Text(
                isLive ? 'AI' : 'On-device',
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Gap.h12,
          if (summary == null) ...<Widget>[
            const SkeletonBox(height: 14),
            Gap.h8,
            const SkeletonBox(height: 14, width: 220),
          ] else
            Text(summary!, style: context.text.bodyMedium),
          Gap.h12,
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push(Routes.chat),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: const Text('Ask about your day'),
            ),
          ),
        ],
      ),
    );
  }
}

class MoodCard extends ConsumerWidget {
  const MoodCard({required this.mood, super.key});

  final MoodEntry? mood;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = mood;

    return GlassCard(
      accent: AppColors.mood,
      onTap: () => context.push(Routes.mood),
      semanticLabel: entry == null
          ? 'No mood logged today'
          : 'Mood: ${entry.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'How you feel'),
          if (entry == null)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Nothing logged yet today.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => context.push(Routes.mood),
                  child: const Text('Check in'),
                ),
              ],
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Text(entry.emoji, style: const TextStyle(fontSize: 34)),
                Gap.w16,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(entry.label, style: context.text.titleMedium),
                    Text(
                      Fmt.relative(entry.recordedAt),
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Gap.h16,
            // Two dimensions only: the card is a glance, the detail lives in
            // the mood screen.
            Row(
              children: <Widget>[
                Expanded(
                  child: _MiniMeter(
                    label: 'Energy',
                    value: entry.energy / 10,
                    color: AppColors.habits,
                  ),
                ),
                Gap.w12,
                Expanded(
                  child: _MiniMeter(
                    label: 'Stress',
                    value: entry.stress / 10,
                    color: AppColors.health,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniMeter extends StatelessWidget {
  const _MiniMeter({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          Gap.h4,
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              color: color,
              backgroundColor: context.colors.surfaceContainerHighest,
            ),
          ),
        ],
      );
}

class HabitRingCard extends ConsumerWidget {
  const HabitRingCard({
    required this.habits,
    required this.completion,
    super.key,
  });

  final List<HabitWithProgress> habits;
  final double completion;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GlassCard(
        accent: AppColors.habits,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: 'Habits',
              subtitle: habits.isEmpty
                  ? 'None scheduled today'
                  : '${habits.where((h) => h.isComplete).length} of '
                      '${habits.length} done',
              onSeeAll: () => context.push(Routes.habits),
            ),
            if (habits.isEmpty)
              Text(
                'Add a habit to start building a streak.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              )
            else
              Row(
                children: <Widget>[
                  ProgressRing(
                    value: completion,
                    color: AppColors.habits,
                    caption: 'today',
                  ),
                  Gap.w16,
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        for (final item in habits.take(4))
                          _HabitRow(item: item),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
}

class _HabitRow extends ConsumerWidget {
  const _HabitRow({required this.item});

  final HabitWithProgress item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
        onTap: () => ref
            .read(dashboardControllerProvider.notifier)
            .toggleHabit(item.habit.id, done: !item.isComplete),
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: <Widget>[
              Text(item.habit.emoji, style: const TextStyle(fontSize: 16)),
              Gap.w8,
              Expanded(
                child: Text(
                  item.habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    decoration: item.isComplete
                        ? TextDecoration.lineThrough
                        : null,
                    color: item.isComplete
                        ? context.colors.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
              if (item.streak > 1)
                Text(
                  '${item.streak}🔥',
                  style: context.text.labelSmall,
                ),
              Gap.w8,
              Icon(
                item.isComplete
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 20,
                color: item.isComplete
                    ? AppColors.habits
                    : context.colors.outline,
              ),
            ],
          ),
        ),
      );
}

class TasksCard extends ConsumerWidget {
  const TasksCard({required this.tasks, super.key});

  final List<Task> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GlassCard(
        accent: AppColors.tasks,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: 'Today’s focus',
              subtitle: tasks.isEmpty ? 'Nothing due' : '${tasks.length} items',
              onSeeAll: () => context.push(Routes.tasks),
            ),
            if (tasks.isEmpty)
              Text(
                'Your list is clear.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              )
            else
              for (final task in tasks)
                CheckboxListTile(
                  value: task.isDone,
                  onChanged: (value) => ref
                      .read(dashboardControllerProvider.notifier)
                      .completeTask(task.id, done: value ?? false),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium,
                  ),
                  subtitle: task.dueAt == null && task.aiReason == null
                      ? null
                      : Text(
                          <String>[
                            if (task.dueAt != null)
                              task.isOverdue
                                  ? 'Overdue'
                                  : 'Due ${Fmt.time(task.dueAt!)}',
                            // The planner's reason for an overdue task is
                            // literally "Overdue", which would read
                            // "Overdue · Overdue" next to the due label.
                            if (task.aiReason != null &&
                                !task.aiReason!
                                    .toLowerCase()
                                    .startsWith('overdue'))
                              task.aiReason!,
                          ].join(' · '),
                          style: context.text.labelSmall?.copyWith(
                            color: task.isOverdue
                                ? context.colors.error
                                : context.colors.onSurfaceVariant,
                          ),
                        ),
                ),
          ],
        ),
      );
}

class UpcomingCard extends StatelessWidget {
  const UpcomingCard({required this.events, super.key});

  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) => GlassCard(
        accent: AppColors.calendar,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: 'Coming up',
              onSeeAll: () => context.push(Routes.calendar),
            ),
            if (events.isEmpty)
              Text(
                'Nothing scheduled.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              )
            else
              for (final event in events)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 3,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(event.colorValue),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                      ),
                      Gap.w12,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyMedium,
                            ),
                            Text(
                              event.allDay
                                  ? 'All day · ${Fmt.weekday(event.start)}'
                                  : '${Fmt.time(event.start)} · '
                                      '${Fmt.weekday(event.start)}',
                              style: context.text.labelSmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (event.isNow)
                        Chip(
                          label: const Text('Now'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
          ],
        ),
      );
}

class MoneyCard extends ConsumerWidget {
  const MoneyCard({required this.spentTodayMinor, super.key});

  final int spentTodayMinor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);

    return GlassCard(
      accent: AppColors.finance,
      onTap: () => context.push(Routes.money),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Spending today'),
          Text(
            Fmt.money(spentTodayMinor, currency: currency),
            style: context.text.headlineMedium,
          ),
          Gap.h8,
          Text(
            spentTodayMinor == 0
                ? 'Nothing logged yet.'
                : 'Tap to see where it went.',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class HealthCard extends ConsumerWidget {
  const HealthCard({required this.summary, super.key});

  final DailyHealthSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GlassCard(
        accent: AppColors.health,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: 'Body',
              onSeeAll: () => context.push(Routes.health),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: 'Sleep',
                    icon: Icons.bedtime_outlined,
                    value: summary.valueOf(HealthKind.sleep) == null
                        ? '—'
                        : Fmt.hours(summary.valueOf(HealthKind.sleep)!),
                    progress: summary.progressOf(HealthKind.sleep),
                    accent: AppColors.insights,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Water',
                    icon: Icons.water_drop_outlined,
                    value:
                        '${summary.valueOf(HealthKind.water)?.toStringAsFixed(0) ?? 0}',
                    unit: 'glasses',
                    progress: summary.progressOf(HealthKind.water),
                    accent: AppColors.calendar,
                    onTap: () => ref
                        .read(dashboardControllerProvider.notifier)
                        .logWater(),
                  ),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: 'Move',
                    icon: Icons.directions_run_rounded,
                    value:
                        '${summary.valueOf(HealthKind.exercise)?.toStringAsFixed(0) ?? 0}',
                    unit: 'min',
                    progress: summary.progressOf(HealthKind.exercise),
                    accent: AppColors.habits,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Screen',
                    icon: Icons.phone_iphone_rounded,
                    value: summary.valueOf(HealthKind.screenTime) == null
                        ? '—'
                        : Fmt.hours(summary.valueOf(HealthKind.screenTime)!),
                    accent: AppColors.goals,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

/// Life score, journal streak and goal progress — the "how am I doing overall"
/// card.
class LifeScoreCard extends ConsumerWidget {
  const LifeScoreCard({
    required this.journalStreak,
    required this.goals,
    super.key,
  });

  final int journalStreak;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = ref.watch(lifeScoreProvider);

    return GlassCard(
      accent: AppColors.goals,
      onTap: () => context.push(Routes.insights),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Life score'),
          Row(
            children: <Widget>[
              score.when(
                data: (value) => ProgressRing(
                  value: value.total / 100,
                  label: '${value.total}',
                  caption: value.band,
                  color: AppColors.forScore(value.total / 100),
                ),
                loading: () => const SizedBox.square(
                  dimension: 64,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
                ),
                error: (_, __) => const SizedBox.square(dimension: 64),
              ),
              Gap.w16,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      journalStreak == 0
                          ? 'No journal streak yet'
                          : '$journalStreak-day journal streak',
                      style: context.text.bodyMedium,
                    ),
                    Gap.h8,
                    if (goals.isEmpty)
                      Text(
                        'No active goals',
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      )
                    else
                      for (final goal in goals)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                goal.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelMedium,
                              ),
                              Gap.h4,
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(Radii.pill),
                                child: LinearProgressIndicator(
                                  value: goal.progress,
                                  minHeight: 5,
                                  color: Color(goal.colorValue),
                                  backgroundColor:
                                      context.colors.surfaceContainerHighest,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
          // The score is meaningless without saying what it could not see.
          score.maybeWhen(
            data: (value) => value.missingPillars.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: Gap.sm),
                    child: Text(
                      'Not counted: ${value.missingPillars.join(', ')}',
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
