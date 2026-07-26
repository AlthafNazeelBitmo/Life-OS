import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/habit.dart';

final StreamProviderFamily<Habit?, String> _habitProvider =
    StreamProvider.family<Habit?, String>(
  (ref, id) => ref.watch(habitRepositoryProvider).watchHabit(id),
);

final FutureProviderFamily<HabitStats, String> _statsProvider =
    FutureProvider.family<HabitStats, String>((ref, id) async {
  // Depends on the habit stream so logging a day recomputes the stats.
  ref.watch(_habitProvider(id));
  final result = await ref.watch(habitRepositoryProvider).stats(id);
  return result.valueOrNull ?? HabitStats(habitId: id);
});

class HabitDetailScreen extends ConsumerWidget {
  const HabitDetailScreen({required this.habitId, super.key});

  final String habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habit = ref.watch(_habitProvider(habitId));
    final stats = ref.watch(_statsProvider(habitId));

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(habit.valueOrNull?.name ?? 'Habit'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Archive',
              onPressed: () async {
                await ref.read(habitRepositoryProvider).archive(habitId);
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.archive_outlined),
            ),
          ],
        ),
        body: AsyncView<Habit?>(
          value: habit,
          builder: (context, value) {
            if (value == null) {
              return const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Habit not found',
              );
            }
            final statValue = stats.valueOrNull ?? HabitStats(habitId: habitId);

            return ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 80),
              children: <Widget>[
                GlassCard(
                  accent: Color(value.colorValue),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            value.emoji,
                            style: const TextStyle(fontSize: 30),
                          ),
                          Gap.w16,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(value.name, style: context.text.titleLarge),
                                Text(
                                  '${value.cadence.name} · '
                                  '${statValue.grade}',
                                  style: context.text.labelSmall?.copyWith(
                                    color: context.colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Gap.h16,
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: StatTile(
                              label: 'Current streak',
                              value: '${statValue.currentStreak}',
                              unit: 'days',
                              icon: Icons.local_fire_department_rounded,
                              accent: Color(value.colorValue),
                            ),
                          ),
                          Expanded(
                            child: StatTile(
                              label: 'Best streak',
                              value: '${statValue.longestStreak}',
                              unit: 'days',
                              icon: Icons.emoji_events_outlined,
                            ),
                          ),
                          Expanded(
                            child: StatTile(
                              label: 'Score',
                              value: '${statValue.score}',
                              icon: Icons.speed_rounded,
                              progress: statValue.score / 100,
                            ),
                          ),
                        ],
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
                        title: 'Last 16 weeks',
                        subtitle:
                            '${Fmt.percent(statValue.completionRate)} of '
                            'scheduled days',
                      ),
                      _Heatmap(heatmap: statValue.heatmap, habit: value),
                    ],
                  ),
                ),
                if (value.notes.isNotEmpty) ...<Widget>[
                  Gap.h16,
                  GlassCard(child: Text(value.notes)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// GitHub-style contribution grid: weeks as columns, weekdays as rows.
///
/// Intensity comes from the theme's sequential ramp, so it stays legible in
/// both light and dark and does not rely on hue alone.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.heatmap, required this.habit});

  final Map<String, int> heatmap;
  final Habit habit;

  static const int _weeks = 16;

  @override
  Widget build(BuildContext context) {
    final ramp = context.theme.tokens.heatRamp;
    final today = DateTime.now().startOfDay;
    final start = today
        .subtract(Duration(days: _weeks * 7))
        .startOfWeek;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var week = 0; week <= _weeks; week++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Column(
                children: <Widget>[
                  for (var weekday = 0; weekday < 7; weekday++)
                    Builder(
                      builder: (context) {
                        final day = start.add(
                          Duration(days: week * 7 + weekday),
                        );
                        if (day.isAfter(today)) {
                          return const SizedBox(width: 13, height: 13);
                        }

                        final logged = heatmap[Fmt.dayKey(day)] ?? 0;
                        final scheduled = habit.isScheduledOn(day);
                        final intensity = habit.target == 0
                            ? 0.0
                            : (logged / habit.target).clamp(0.0, 1.0);
                        final index =
                            (intensity * (ramp.length - 1)).round();

                        return Tooltip(
                          message: '${Fmt.shortDate(day)}: '
                              '${logged > 0 ? '$logged logged' : scheduled ? 'missed' : 'not scheduled'}',
                          child: Container(
                            width: 13,
                            height: 13,
                            margin: const EdgeInsets.only(bottom: 3),
                            decoration: BoxDecoration(
                              color: ramp[index],
                              borderRadius: BorderRadius.circular(3),
                              // Days the habit was never due are outlined
                              // rather than filled, so a rest day does not read
                              // as a failure.
                              border: scheduled || logged > 0
                                  ? null
                                  : Border.all(
                                      color: context.colors.outlineVariant,
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
