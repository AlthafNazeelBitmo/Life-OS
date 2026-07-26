import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../domain/entities/journal_entry.dart';
import '../application/journal_controller.dart';

class JournalEntryScreen extends ConsumerWidget {
  const JournalEntryScreen({required this.entryId, super.key});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(journalEntryProvider(entryId));

    return AppBackdrop(
      accent: AppColors.journal,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          actions: <Widget>[
            IconButton(
              tooltip: 'Edit',
              onPressed: () =>
                  context.push('${Routes.journalCompose}?id=$entryId'),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: AsyncView<JournalEntry?>(
          value: entry,
          builder: (context, value) {
            if (value == null) {
              return const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Entry not found',
                message: 'It may have been deleted.',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 80),
              children: <Widget>[
                Text(
                  Fmt.longDate(value.createdAt),
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                Gap.h8,
                Text(value.displayTitle, style: context.text.headlineSmall),
                if (value.location?.name != null ||
                    value.weather != null) ...<Widget>[
                  Gap.h8,
                  Row(
                    children: <Widget>[
                      if (value.location?.name != null) ...<Widget>[
                        const Icon(Icons.place_outlined, size: 14),
                        Gap.w4,
                        Text(
                          value.location!.name!,
                          style: context.text.labelSmall,
                        ),
                        Gap.w12,
                      ],
                      if (value.weather != null) ...<Widget>[
                        const Icon(Icons.cloud_outlined, size: 14),
                        Gap.w4,
                        Text(value.weather!, style: context.text.labelSmall),
                      ],
                    ],
                  ),
                ],
                Gap.h24,
                SelectableText(
                  value.body,
                  style: context.text.bodyLarge?.copyWith(height: 1.6),
                ),
                if (value.analysis != null) ...<Widget>[
                  Gap.h32,
                  _AnalysisCard(analysis: value.analysis!),
                ],
                if (value.tags.isNotEmpty) ...<Widget>[
                  Gap.h24,
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: Gap.xs,
                    children: <Widget>[
                      for (final tag in value.tags) Chip(label: Text(tag)),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// What the assistant took from the entry.
///
/// Presented as the app's reading of the text, clearly attributed and clearly
/// secondary — the user's own words stay the main content of the screen.
class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.analysis});

  final JournalAnalysis analysis;

  @override
  Widget build(BuildContext context) => GlassCard(
        accent: AppColors.insights,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.auto_awesome_rounded, size: 16),
                Gap.w8,
                Text('What I noticed', style: context.text.titleSmall),
                const Spacer(),
                if (analysis.model != null)
                  Text(
                    analysis.model!,
                    style: context.text.labelSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (analysis.summary != null) ...<Widget>[
              Gap.h12,
              Text(analysis.summary!, style: context.text.bodyMedium),
            ],
            if (analysis.emotions.isNotEmpty) ...<Widget>[
              Gap.h16,
              Text(
                'Emotions',
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              Gap.h4,
              Wrap(
                spacing: Gap.xs,
                children: <Widget>[
                  for (final emotion in analysis.emotions)
                    Chip(
                      label: Text(emotion),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (analysis.events.isNotEmpty) ...<Widget>[
              Gap.h16,
              Text(
                'Worth remembering',
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              Gap.h4,
              for (final event in analysis.events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('• $event', style: context.text.bodySmall),
                ),
            ],
            if (analysis.sentiment != null) ...<Widget>[
              Gap.h16,
              Row(
                children: <Widget>[
                  Text('Tone', style: context.text.labelSmall),
                  Gap.w12,
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: LinearProgressIndicator(
                        // Remapped from -1…1 to 0…1 for display.
                        value: (analysis.sentiment! + 1) / 2,
                        minHeight: 6,
                        color: AppColors.forScore(
                          (analysis.sentiment! + 1) / 2,
                        ),
                        backgroundColor:
                            context.colors.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}
