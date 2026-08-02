import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/chip_strip.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/insight.dart';
import '../../../services/analytics/life_score_service.dart';

final StreamProvider<List<Insight>> insightsProvider =
    StreamProvider<List<Insight>>(
  (ref) => ref.watch(insightRepositoryProvider).watchInsights(),
);

/// Generates fresh insights and persists them.
///
/// Kept as an explicit action rather than an on-open side effect: it costs a
/// model call, and insights that regenerate every time you glance at the screen
/// stop feeling like observations and start feeling like noise.
final AutoDisposeFutureProvider<int> generateInsightsProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final now = DateTime.now();
  final lifeContext = await ref.watch(contextBuilderProvider).forRange(
        from: now.subtract(const Duration(days: 30)),
        to: now.endOfDay,
      );

  final result = await ref.watch(aiServiceProvider).generateInsights(lifeContext);
  final insights = result.valueOrNull ?? const <Insight>[];
  if (insights.isNotEmpty) {
    await ref.watch(insightRepositoryProvider).saveAll(insights);
  }
  return insights.length;
});

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  bool _generating = false;

  Future<void> _generate() async {
    setState(() => _generating = true);
    // Invalidate, then await the rebuilt future: `refresh` returns a value the
    // caller is expected to use, and here only the side effect matters.
    ref.invalidate(generateInsightsProvider);
    await ref.read(generateInsightsProvider.future);
    if (mounted) setState(() => _generating = false);
  }

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(insightsProvider);
    final score = ref.watch(lifeScoreProvider);

    return AppBackdrop(
      accent: AppColors.insights,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar.large(
              backgroundColor: Colors.transparent,
              title: const Text('Insights'),
              actions: <Widget>[
                IconButton(
                  tooltip: 'Timeline',
                  onPressed: () => context.push(Routes.timeline),
                  icon: const Icon(Icons.timeline_rounded),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 120),
              sliver: SliverList.list(
                children: <Widget>[
                  GlassCard(
                    accent: AppColors.goals,
                    child: score.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(Gap.lg),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (_, __) => const Text('Score unavailable.'),
                      data: (value) => _LifeScoreBreakdown(score: value),
                    ),
                  ),
                  Gap.h16,
                  ChipStrip(
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      for (final period in ReviewPeriod.values)
                        ActionChip(
                          label: Text(period.name),
                          onPressed: () =>
                              context.push(Routes.reviewFor(period.name)),
                        ),
                    ],
                  ),
                  Gap.h16,
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Patterns',
                          style: context.text.titleMedium,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _generating ? null : _generate,
                        icon: _generating
                            ? const SizedBox.square(
                                dimension: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: Text(_generating ? 'Thinking…' : 'Refresh'),
                      ),
                    ],
                  ),
                  Gap.h12,
                  insights.when(
                    loading: () => const SkeletonBox(height: 120),
                    error: (error, _) => Text('Could not load insights: $error'),
                    data: (items) => items.isEmpty
                        ? const EmptyState(
                            icon: Icons.insights_outlined,
                            title: 'No patterns yet',
                            message: 'Log a couple of weeks and LifeOS will '
                                'start noticing what moves your days.',
                          )
                        : Column(
                            children: <Widget>[
                              for (final insight in items)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: Gap.md),
                                  child: _InsightCard(insight: insight),
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

class _LifeScoreBreakdown extends StatelessWidget {
  const _LifeScoreBreakdown({required this.score});

  final LifeScore score;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(
            title: 'Life score',
            subtitle: 'Computed on this device from the last two weeks',
          ),
          Row(
            children: <Widget>[
              ProgressRing(
                value: score.total / 100,
                size: 84,
                label: '${score.total}',
                caption: score.band,
                color: AppColors.forScore(score.total / 100),
              ),
              Gap.w24,
              Expanded(
                child: Column(
                  children: <Widget>[
                    for (final entry in score.pillars.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 88,
                              child: Text(
                                entry.key,
                                style: context.text.labelSmall,
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(Radii.pill),
                                child: LinearProgressIndicator(
                                  value: entry.value / 100,
                                  minHeight: 6,
                                  color: score.missingPillars
                                          .contains(entry.key)
                                      ? context.colors.outlineVariant
                                      : AppColors.forScore(entry.value / 100),
                                  backgroundColor:
                                      context.colors.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            Gap.w8,
                            SizedBox(
                              width: 34,
                              child: Text(
                                score.missingPillars.contains(entry.key)
                                    ? '—'
                                    : '${entry.value}',
                                style: context.text.labelSmall,
                                textAlign: TextAlign.end,
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
        ],
      );
}

class _InsightCard extends ConsumerWidget {
  const _InsightCard({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = switch (insight.kind) {
      InsightKind.achievement => AppColors.positive,
      InsightKind.warning => AppColors.negative,
      InsightKind.recommendation => AppColors.goals,
      InsightKind.correlation => AppColors.insights,
      InsightKind.milestone => AppColors.habits,
      InsightKind.pattern => AppColors.calendar,
    };

    return GlassCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                switch (insight.kind) {
                  InsightKind.achievement => Icons.emoji_events_outlined,
                  InsightKind.warning => Icons.warning_amber_rounded,
                  InsightKind.recommendation => Icons.lightbulb_outline_rounded,
                  InsightKind.correlation => Icons.hub_outlined,
                  InsightKind.milestone => Icons.flag_outlined,
                  InsightKind.pattern => Icons.insights_rounded,
                },
                size: 18,
                color: accent,
              ),
              Gap.w8,
              Expanded(
                child: Text(insight.title, style: context.text.titleSmall),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: insight.pinned ? 'Unpin' : 'Pin',
                onPressed: () => ref
                    .read(insightRepositoryProvider)
                    .setPinned(insight.id, pinned: !insight.pinned),
                icon: Icon(
                  insight.pinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  size: 18,
                ),
              ),
            ],
          ),
          Gap.h8,
          Text(insight.body, style: context.text.bodyMedium),
          // Tentative findings are labelled rather than hidden: the user can
          // judge a weak signal, but not one that was presented as certain.
          if (insight.isTentative) ...<Widget>[
            Gap.h8,
            Row(
              children: <Widget>[
                Icon(
                  Icons.help_outline_rounded,
                  size: 13,
                  color: context.colors.onSurfaceVariant,
                ),
                Gap.w4,
                Text(
                  'Possible pattern — not enough data to be sure',
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (insight.citations.isNotEmpty) ...<Widget>[
            Gap.h12,
            Wrap(
              spacing: Gap.xs,
              runSpacing: Gap.xs,
              children: <Widget>[
                for (final citation in insight.citations.take(4))
                  Chip(
                    label: Text(citation.label),
                    visualDensity: VisualDensity.compact,
                    labelStyle: context.text.labelSmall,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
