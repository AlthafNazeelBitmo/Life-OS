import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/habit.dart';
import '../../../domain/repositories/habit_repository.dart';

final StreamProvider<List<HabitWithProgress>> todayHabitsProvider =
    StreamProvider<List<HabitWithProgress>>(
  (ref) => ref.watch(habitRepositoryProvider).watchForDay(DateTime.now()),
);

/// AI habit proposals, generated on demand rather than on open — suggestions
/// nobody asked for are noise, and they cost a model call.
final FutureProvider<List<HabitSuggestion>> habitSuggestionsProvider =
    FutureProvider<List<HabitSuggestion>>((ref) async {
  final now = DateTime.now();
  final context = await ref.watch(contextBuilderProvider).forRange(
        from: now.subtract(const Duration(days: 30)),
        to: now.endOfDay,
      );
  final result = await ref.watch(aiServiceProvider).suggestHabits(context);
  return result.valueOrNull ?? const <HabitSuggestion>[];
});

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(todayHabitsProvider);

    return AppBackdrop(
      accent: AppColors.habits,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Habits'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'habit-fab',
          onPressed: () => _createHabit(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New habit'),
        ),
        body: AsyncView<List<HabitWithProgress>>(
          value: habits,
          builder: (context, items) => ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 120),
            children: <Widget>[
              if (items.isEmpty)
                EmptyState(
                  icon: Icons.repeat_rounded,
                  title: 'No habits yet',
                  message: 'Small and repeatable beats ambitious and abandoned.',
                  action: FilledButton(
                    onPressed: () => _createHabit(context, ref),
                    child: const Text('Add your first'),
                  ),
                )
              else ...<Widget>[
                _TodayRing(items: items),
                Gap.h16,
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: _HabitTile(item: item),
                  ),
              ],
              Gap.h24,
              const _Suggestions(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createHabit(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    var cadence = HabitCadence.daily;
    var emoji = '✅';

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
                Text('New habit', style: sheetContext.text.titleLarge),
                Gap.h16,
                TextField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                Gap.h16,
                Wrap(
                  spacing: Gap.xs,
                  children: <Widget>[
                    for (final option in <String>[
                      '✅', '🏃', '📚', '🧘', '💧', '🛏️', '🎯', '🎸',
                    ])
                      ChoiceChip(
                        label: Text(option),
                        selected: emoji == option,
                        onSelected: (_) => setSheetState(() => emoji = option),
                      ),
                  ],
                ),
                Gap.h16,
                SegmentedButton<HabitCadence>(
                  segments: const <ButtonSegment<HabitCadence>>[
                    ButtonSegment<HabitCadence>(
                      value: HabitCadence.daily,
                      label: Text('Daily'),
                    ),
                    ButtonSegment<HabitCadence>(
                      value: HabitCadence.weekly,
                      label: Text('Weekly'),
                    ),
                    ButtonSegment<HabitCadence>(
                      value: HabitCadence.monthly,
                      label: Text('Monthly'),
                    ),
                  ],
                  selected: <HabitCadence>{cadence},
                  onSelectionChanged: (values) =>
                      setSheetState(() => cadence = values.first),
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

    if (confirmed != true || name.text.trim().isEmpty) return;
    await ref.read(habitRepositoryProvider).upsert(
          Habit(
            id: newId(),
            name: name.text.trim(),
            createdAt: DateTime.now(),
            emoji: emoji,
            cadence: cadence,
          ),
        );
  }
}

class _TodayRing extends StatelessWidget {
  const _TodayRing({required this.items});

  final List<HabitWithProgress> items;

  @override
  Widget build(BuildContext context) {
    final done = items.where((item) => item.isComplete).length;

    return GlassCard(
      accent: AppColors.habits,
      child: Row(
        children: <Widget>[
          ProgressRing(
            value: items.isEmpty ? 0 : done / items.length,
            size: 78,
            color: AppColors.habits,
            caption: 'today',
          ),
          Gap.w24,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('$done of ${items.length} done',
                    style: context.text.titleMedium),
                Gap.h4,
                Text(
                  done == items.length
                      ? 'Everything scheduled is complete.'
                      : 'Keep the streak alive.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitTile extends ConsumerWidget {
  const _HabitTile({required this.item});

  final HabitWithProgress item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habit = item.habit;

    return GlassCard(
      accent: Color(habit.colorValue),
      onTap: () => context.push(Routes.habitDetailFor(habit.id)),
      padding: Insets.cardCompact,
      child: Row(
        children: <Widget>[
          Text(habit.emoji, style: const TextStyle(fontSize: 24)),
          Gap.w16,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(habit.name, style: context.text.titleSmall),
                Gap.h4,
                Text(
                  <String>[
                    if (item.streak > 0) '${item.streak} day streak',
                    if (habit.kind == HabitKind.quantity)
                      '${item.loggedAmount}/${habit.target} ${habit.unit}',
                  ].join(' · '),
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: item.isComplete ? 'Undo' : 'Mark done',
            onPressed: () => ref.read(habitRepositoryProvider).log(
                  habit.id,
                  DateTime.now(),
                  amount: item.isComplete ? 0 : habit.target,
                ),
            icon: Icon(
              item.isComplete
                  ? Icons.check_rounded
                  : Icons.radio_button_unchecked_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _Suggestions extends ConsumerWidget {
  const _Suggestions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(habitSuggestionsProvider);

    return GlassCard(
      accent: AppColors.insights,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Suggested for you',
            subtitle: 'Based on your journal, goals and sleep',
            trailing: IconButton(
              tooltip: 'Regenerate',
              onPressed: () => ref.invalidate(habitSuggestionsProvider),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          suggestions.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: Gap.md),
              child: SkeletonBox(height: 60),
            ),
            error: (_, __) => Text(
              'Suggestions are unavailable right now.',
              style: context.text.bodySmall,
            ),
            data: (items) => items.isEmpty
                ? Text(
                    'Nothing to suggest yet — log a few more days first.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (final suggestion in items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Text(
                            suggestion.emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                          title: Text(suggestion.name),
                          subtitle: Text(
                            suggestion.rationale,
                            style: context.text.labelSmall,
                          ),
                          trailing: IconButton(
                            tooltip: 'Add this habit',
                            onPressed: () async {
                              await ref.read(habitRepositoryProvider).upsert(
                                    Habit(
                                      id: newId(),
                                      name: suggestion.name,
                                      createdAt: DateTime.now(),
                                      emoji: suggestion.emoji,
                                      cadence: suggestion.cadence,
                                      target: suggestion.target,
                                      unit: suggestion.unit,
                                      kind: suggestion.target > 1
                                          ? HabitKind.quantity
                                          : HabitKind.binary,
                                    ),
                                  );
                              if (context.mounted) {
                                context.showSnack('Added ${suggestion.name}');
                              }
                            },
                            icon: const Icon(Icons.add_circle_outline_rounded),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
