import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/goal.dart';

final StreamProvider<List<Goal>> goalsProvider = StreamProvider<List<Goal>>(
  (ref) => ref.watch(goalRepositoryProvider).watchGoals(),
);

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);

    return AppBackdrop(
      accent: AppColors.goals,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Goals'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'goal-fab',
          onPressed: () => _createGoal(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New goal'),
        ),
        body: AsyncView<List<Goal>>(
          value: goals,
          builder: (context, items) {
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.flag_outlined,
                title: 'No goals yet',
                message: 'Name one thing you want to be true in six months.',
                action: FilledButton(
                  onPressed: () => _createGoal(context, ref),
                  child: const Text('Set a goal'),
                ),
              );
            }

            final active =
                items.where((g) => g.status == GoalStatus.active).toList();
            final done =
                items.where((g) => g.status == GoalStatus.achieved).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 120),
              children: <Widget>[
                for (final goal in active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: _GoalCard(goal: goal),
                  ),
                if (done.isNotEmpty) ...<Widget>[
                  Gap.h16,
                  Text('Achieved', style: context.text.titleSmall),
                  Gap.h8,
                  for (final goal in done)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: _GoalCard(goal: goal),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _createGoal(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final description = TextEditingController();
    var horizon = GoalHorizon.shortTerm;
    DateTime? target;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Padding(
            padding: Insets.sheet,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('New goal', style: sheetContext.text.titleLarge),
                Gap.h16,
                TextField(
                  controller: title,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'What do you want to achieve?',
                  ),
                ),
                Gap.h12,
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Why does it matter? (optional)',
                  ),
                ),
                Gap.h16,
                SegmentedButton<GoalHorizon>(
                  segments: const <ButtonSegment<GoalHorizon>>[
                    ButtonSegment<GoalHorizon>(
                      value: GoalHorizon.shortTerm,
                      label: Text('Short term'),
                    ),
                    ButtonSegment<GoalHorizon>(
                      value: GoalHorizon.longTerm,
                      label: Text('Long term'),
                    ),
                  ],
                  selected: <GoalHorizon>{horizon},
                  onSelectionChanged: (values) =>
                      setSheetState(() => horizon = values.first),
                ),
                Gap.h12,
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: sheetContext,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 3650)),
                      initialDate: now.add(const Duration(days: 90)),
                    );
                    if (picked != null) setSheetState(() => target = picked);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    target == null
                        ? 'Add a deadline'
                        : Fmt.shortDate(target!),
                  ),
                ),
                Gap.h24,
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('Create'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || title.text.trim().isEmpty) return;
    await ref.read(goalRepositoryProvider).upsert(
          Goal(
            id: newId(),
            title: title.text.trim(),
            createdAt: DateTime.now(),
            description: description.text.trim(),
            horizon: horizon,
            targetDate: target,
          ),
        );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) => GlassCard(
        accent: Color(goal.colorValue),
        onTap: () => context.push(Routes.goalDetailFor(goal.id)),
        semanticLabel:
            '${goal.title}, ${(goal.progress * 100).round()} percent complete',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(goal.title, style: context.text.titleSmall),
                ),
                if (goal.isAtRisk)
                  Tooltip(
                    message: 'Behind the pace needed to hit the deadline',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: context.colors.error,
                    ),
                  ),
              ],
            ),
            Gap.h8,
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                value: goal.progress,
                minHeight: 7,
                color: Color(goal.colorValue),
                backgroundColor: context.colors.surfaceContainerHighest,
              ),
            ),
            Gap.h8,
            Row(
              children: <Widget>[
                Text(
                  Fmt.percent(goal.progress),
                  style: context.text.labelMedium,
                ),
                const Spacer(),
                if (goal.targetDate != null)
                  Text(
                    goal.isOverdue
                        ? 'Overdue'
                        : '${goal.daysRemaining} days left',
                    style: context.text.labelSmall?.copyWith(
                      color: goal.isOverdue
                          ? context.colors.error
                          : context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (goal.nextMilestone != null) ...<Widget>[
              Gap.h8,
              Text(
                'Next: ${goal.nextMilestone!.title}',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
}
