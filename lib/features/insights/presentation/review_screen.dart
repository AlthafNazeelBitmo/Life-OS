import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/insight.dart';
import '../../../services/export/export_service.dart';

/// Period boundaries for a review, so the same code serves week → year.
({DateTime from, DateTime to}) _windowFor(ReviewPeriod period) {
  final now = DateTime.now();
  return switch (period) {
    ReviewPeriod.weekly => (from: now.startOfWeek, to: now.endOfWeek),
    ReviewPeriod.monthly => (from: now.startOfMonth, to: now.endOfMonth),
    ReviewPeriod.quarterly => (from: now.startOfQuarter, to: now.endOfQuarter),
    ReviewPeriod.yearly => (from: now.startOfYear, to: now.endOfYear),
  };
}

/// Loads a stored review, generating one only if none exists for this period.
///
/// Reviews are expensive and stable — regenerating on every visit would both
/// cost money and change the user's own record of a period they already read.
final FutureProviderFamily<PeriodReview, ReviewPeriod> reviewProvider =
    FutureProvider.family<PeriodReview, ReviewPeriod>((ref, period) async {
  final window = _windowFor(period);
  final repository = ref.watch(insightRepositoryProvider);

  final existing = await repository.findReview(period, window.from);
  final stored = existing.valueOrNull;
  if (stored != null) return stored;

  final lifeContext = await ref.watch(contextBuilderProvider).forRange(
        from: window.from,
        to: window.to,
        maxChunks: 120,
      );
  final result =
      await ref.watch(aiServiceProvider).periodReview(period, lifeContext);

  return result.fold(
    (review) async {
      await repository.saveReview(review);
      return review;
    },
    (failure) => throw failure,
  );
});

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({required this.periodId, super.key});

  final String periodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ReviewPeriod.values.firstWhere(
      (value) => value.name == periodId,
      orElse: () => ReviewPeriod.weekly,
    );
    final review = ref.watch(reviewProvider(period));

    return AppBackdrop(
      accent: AppColors.insights,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(period.label),
          actions: <Widget>[
            IconButton(
              tooltip: 'Regenerate',
              onPressed: () => ref.invalidate(reviewProvider(period)),
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Export as PDF',
              onPressed: () async {
                final value = review.valueOrNull;
                if (value == null) return;
                final service = ref.read(exportServiceProvider);
                final file = await service.exportReviewPdf(value);
                await file.fold(
                  (pdf) => service.share(<File>[pdf], subject: period.label),
                  (failure) async {
                    if (context.mounted) context.showError(failure.message);
                  },
                );
              },
              icon: const Icon(Icons.ios_share_rounded),
            ),
          ],
        ),
        body: AsyncView<PeriodReview>(
          value: review,
          loading: const _ReviewSkeleton(),
          onRetry: () => ref.invalidate(reviewProvider(period)),
          builder: (context, value) => ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 80),
            children: <Widget>[
              Text(
                '${Fmt.shortDate(value.periodStart)} — '
                '${Fmt.shortDate(value.periodEnd)}',
                style: context.text.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              Gap.h8,
              if (value.headline.isNotEmpty)
                Text(value.headline, style: context.text.headlineSmall),
              Gap.h16,
              GlassCard(child: Text(value.narrative)),
              if (value.wins.isNotEmpty) ...<Widget>[
                Gap.h16,
                _ListCard(
                  title: 'Wins',
                  icon: Icons.emoji_events_outlined,
                  accent: AppColors.positive,
                  items: value.wins,
                ),
              ],
              if (value.attentionAreas.isNotEmpty) ...<Widget>[
                Gap.h16,
                _ListCard(
                  title: 'Needs attention',
                  icon: Icons.warning_amber_rounded,
                  accent: AppColors.caution,
                  items: value.attentionAreas,
                ),
              ],
              if (value.recommendations.isNotEmpty) ...<Widget>[
                Gap.h16,
                _ListCard(
                  title: 'For next ${period.name.replaceAll('ly', '')}',
                  icon: Icons.lightbulb_outline_rounded,
                  accent: AppColors.goals,
                  items: value.recommendations,
                ),
              ],
              if (value.metrics.isNotEmpty) ...<Widget>[
                Gap.h16,
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SectionHeader(title: 'By the numbers'),
                      for (final entry in value.metrics.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: context.text.bodySmall,
                                ),
                              ),
                              Text(
                                entry.value.toStringAsFixed(
                                  entry.value % 1 == 0 ? 0 : 1,
                                ),
                                style: context.text.labelMedium,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              Gap.h24,
              Text(
                value.model == null
                    ? 'Generated on this device'
                    : 'Generated with ${value.model}',
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final List<String> items;

  @override
  Widget build(BuildContext context) => GlassCard(
        accent: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18, color: accent),
                Gap.w8,
                Text(title, style: context.text.titleSmall),
              ],
            ),
            Gap.h12,
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('•  ', style: context.text.bodyMedium),
                    Expanded(
                      child: Text(item, style: context.text.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _ReviewSkeleton extends StatelessWidget {
  const _ReviewSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: <Widget>[
          const SkeletonBox(height: 14, width: 180),
          Gap.h16,
          const SkeletonBox(height: 28, width: 260),
          Gap.h24,
          const SkeletonBox(height: 120, radius: Radii.lg),
          Gap.h16,
          const SkeletonBox(height: 90, radius: Radii.lg),
          Gap.h24,
          Center(
            child: Text(
              'Reading your last few weeks…',
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
}
