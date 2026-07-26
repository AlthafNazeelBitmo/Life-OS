import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/calendar_event.dart';
import '../../../domain/entities/task.dart';

/// Today's agenda: events and tasks on one timeline, plus an AI day plan that
/// works around what is already committed.
final FutureProvider<DayPlan> dayPlanProvider =
    FutureProvider<DayPlan>((ref) async {
  final now = DateTime.now();
  final tasks = await ref.watch(taskRepositoryProvider).watchToday().first;
  final lifeContext = await ref.watch(contextBuilderProvider).forRange(
        from: now.startOfDay,
        to: now.endOfDay,
        maxChunks: 30,
      );

  final result = await ref.watch(aiServiceProvider).planDay(
        date: now,
        tasks: tasks,
        context: lifeContext,
      );
  return result.fold((plan) => plan, (failure) => throw failure);
});

final StreamProvider<List<CalendarEvent>> _todayEventsProvider =
    StreamProvider<List<CalendarEvent>>(
  (ref) => ref.watch(calendarRepositoryProvider).watchDay(DateTime.now()),
);

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(_todayEventsProvider).valueOrNull ?? const [];
    final tasks = ref.watch(_todayTasksProvider).valueOrNull ?? const [];
    final plan = ref.watch(dayPlanProvider);

    return AppBackdrop(
      accent: AppColors.calendar,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar.large(
              backgroundColor: Colors.transparent,
              title: const Text('Plan'),
              actions: <Widget>[
                IconButton(
                  tooltip: 'Calendar',
                  onPressed: () => context.push(Routes.calendar),
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
                IconButton(
                  tooltip: 'All tasks',
                  onPressed: () => context.push(Routes.tasks),
                  icon: const Icon(Icons.checklist_rounded),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 120),
              sliver: SliverList.list(
                children: <Widget>[
                  GlassCard(
                    accent: AppColors.insights,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SectionHeader(
                          title: 'Suggested shape for today',
                          subtitle: Fmt.longDate(DateTime.now()),
                          trailing: IconButton(
                            tooltip: 'Re-plan',
                            onPressed: () => ref.invalidate(dayPlanProvider),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ),
                        plan.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: Gap.lg),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (error, _) => Text(
                            'Could not build a plan right now.',
                            style: context.text.bodySmall,
                          ),
                          data: (value) => _PlanBody(plan: value),
                        ),
                      ],
                    ),
                  ),
                  Gap.h16,
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SectionHeader(
                          title: 'Agenda',
                          subtitle: events.isEmpty
                              ? 'Nothing scheduled'
                              : '${events.length} events',
                        ),
                        if (events.isEmpty)
                          Text(
                            'Your calendar is clear today.',
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          )
                        else
                          for (final event in events)
                            _AgendaRow(
                              time: event.allDay
                                  ? 'All day'
                                  : Fmt.time(event.start),
                              title: event.title,
                              subtitle: event.location,
                              color: Color(event.colorValue),
                              isNow: event.isNow,
                            ),
                      ],
                    ),
                  ),
                  Gap.h16,
                  GlassCard(
                    accent: AppColors.tasks,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SectionHeader(
                          title: 'Due today',
                          onSeeAll: () => context.push(Routes.tasks),
                        ),
                        if (tasks.isEmpty)
                          Text(
                            'Nothing due.',
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          )
                        else
                          for (final task in tasks)
                            CheckboxListTile(
                              value: task.isDone,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              onChanged: (value) => ref
                                  .read(taskRepositoryProvider)
                                  .complete(task.id, done: value ?? false),
                              title: Text(task.title),
                              subtitle: task.dueAt == null
                                  ? null
                                  : Text(
                                      task.isOverdue
                                          ? 'Overdue'
                                          : Fmt.time(task.dueAt!),
                                      style: context.text.labelSmall?.copyWith(
                                        color: task.isOverdue
                                            ? context.colors.error
                                            : null,
                                      ),
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
      ),
    );
  }
}

final StreamProvider<List<Task>> _todayTasksProvider =
    StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchToday(),
);

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.plan});

  final DayPlan plan;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (plan.summary != null)
            Text(plan.summary!, style: context.text.bodyMedium),
          Gap.h12,
          for (final block in plan.blocks)
            _AgendaRow(
              time: '${Fmt.time(block.start)}–${Fmt.time(block.end)}',
              title: block.title,
              subtitle: block.reason,
              color: block.isFocusBlock
                  ? AppColors.insights
                  : context.colors.outline,
              isNow: false,
            ),
          // Naming what is *not* happening is the honest half of a plan.
          if (plan.deferred.isNotEmpty) ...<Widget>[
            Gap.h12,
            Text(
              'Not today',
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            for (final item in plan.deferred)
              Text('• $item', style: context.text.bodySmall),
          ],
        ],
      );
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.time,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isNow,
  });

  final String time;
  final String title;
  final String subtitle;
  final Color color;
  final bool isNow;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 92,
              child: Text(
                time,
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            Container(
              width: 3,
              height: 30,
              margin: const EdgeInsets.only(right: Gap.md),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          title,
                          style: context.text.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isNow) ...<Widget>[
                        Gap.w8,
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.primaryContainer,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text('now', style: context.text.labelSmall),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}
