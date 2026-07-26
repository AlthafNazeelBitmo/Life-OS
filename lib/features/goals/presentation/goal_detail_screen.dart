import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/goal.dart';

final StreamProviderFamily<Goal?, String> _goalProvider =
    StreamProvider.family<Goal?, String>(
  (ref, id) => ref.watch(goalRepositoryProvider).watchGoal(id),
);

class GoalDetailScreen extends ConsumerStatefulWidget {
  const GoalDetailScreen({required this.goalId, super.key});

  final String goalId;

  @override
  ConsumerState<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends ConsumerState<GoalDetailScreen> {
  bool _planning = false;

  /// Asks the assistant to break the goal down, then writes the result as real
  /// milestones and tasks. A plan you cannot act on is just advice.
  Future<void> _generatePlan(Goal goal) async {
    setState(() => _planning = true);
    final now = DateTime.now();

    final lifeContext = await ref.read(contextBuilderProvider).forRange(
          from: now.subtract(const Duration(days: 30)),
          to: now.endOfDay,
        );
    final plan = await ref.read(aiServiceProvider).planGoal(goal, lifeContext);

    if (!mounted) return;
    await plan.fold(
      (value) async {
        final applied =
            await ref.read(goalRepositoryProvider).applyPlan(value);
        if (!mounted) return;
        applied.fold(
          (_) => context.showSnack('Plan added to your goal'),
          (failure) => context.showError(failure.message),
        );
      },
      (failure) async => context.showError(failure.message),
    );
    if (mounted) setState(() => _planning = false);
  }

  Future<void> _addMilestone(Goal goal) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New milestone'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return;

    await ref.read(goalRepositoryProvider).upsertMilestone(
          Milestone(
            id: newId(),
            goalId: goal.id,
            title: title.trim(),
            position: goal.milestones.length,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final goal = ref.watch(_goalProvider(widget.goalId));

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(goal.valueOrNull?.title ?? 'Goal'),
        ),
        body: AsyncView<Goal?>(
          value: goal,
          builder: (context, value) {
            if (value == null) {
              return const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Goal not found',
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 80),
              children: <Widget>[
                GlassCard(
                  accent: Color(value.colorValue),
                  child: Row(
                    children: <Widget>[
                      ProgressRing(
                        value: value.progress,
                        size: 80,
                        color: Color(value.colorValue),
                      ),
                      Gap.w24,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(value.title, style: context.text.titleMedium),
                            if (value.description.isNotEmpty) ...<Widget>[
                              Gap.h4,
                              Text(
                                value.description,
                                style: context.text.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (value.targetDate != null) ...<Widget>[
                              Gap.h8,
                              Text(
                                'Target: ${Fmt.shortDate(value.targetDate!)}',
                                style: context.text.labelSmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (value.isAtRisk) ...<Widget>[
                  Gap.h12,
                  GlassCard(
                    accent: context.colors.error,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.warning_amber_rounded,
                          color: context.colors.error,
                        ),
                        Gap.w12,
                        Expanded(
                          child: Text(
                            'Progress is behind the pace needed for this '
                            'deadline. Consider moving the date or cutting '
                            'scope — both are better than quiet failure.',
                            style: context.text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Gap.h16,
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: 'Milestones',
                        trailing: IconButton(
                          tooltip: 'Add milestone',
                          onPressed: () => _addMilestone(value),
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ),
                      if (value.milestones.isEmpty)
                        Text(
                          'No milestones yet — break it into steps you can '
                          'finish in a week.',
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        )
                      else
                        for (final milestone in value.milestones)
                          CheckboxListTile(
                            value: milestone.isDone,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (checked) => ref
                                .read(goalRepositoryProvider)
                                .toggleMilestone(
                                  milestone.id,
                                  done: checked ?? false,
                                ),
                            title: Text(
                              milestone.title,
                              style: context.text.bodyMedium?.copyWith(
                                decoration: milestone.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: milestone.dueDate == null
                                ? null
                                : Text(
                                    Fmt.shortDate(milestone.dueDate!),
                                    style: context.text.labelSmall,
                                  ),
                          ),
                      Gap.h12,
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed:
                              _planning ? null : () => _generatePlan(value),
                          icon: _planning
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded),
                          label: Text(
                            _planning
                                ? 'Working on a plan…'
                                : 'Break this into a plan',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
