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

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  /// Loads the next page a screen's height before the end, so the list never
  /// visibly stalls at the bottom.
  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - 600) {
      ref.read(journalFeedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(journalFeedProvider);
    final streak = ref.watch(journalStreakProvider).valueOrNull ?? 0;
    final memories = ref.watch(onThisDayProvider).valueOrNull ?? const [];

    return AppBackdrop(
      accent: AppColors.journal,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'journal-fab',
          onPressed: () => context.push(Routes.journalCompose),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Write'),
        ),
        body: CustomScrollView(
          controller: _scroll,
          slivers: <Widget>[
            SliverAppBar.large(
              backgroundColor: Colors.transparent,
              title: const Text('Journal'),
              actions: <Widget>[
                if (streak > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.sm),
                    child: Chip(
                      avatar: const Text('🔥'),
                      label: Text('$streak'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: Insets.page,
                child: SearchBar(
                  controller: _search,
                  hintText: 'Search your entries',
                  leading: const Icon(Icons.search_rounded),
                  onChanged: (value) =>
                      ref.read(journalFeedProvider.notifier).search(value),
                  trailing: <Widget>[
                    if (_search.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          ref.read(journalFeedProvider.notifier).search('');
                        },
                      ),
                  ],
                ),
              ),
            ),
            if (memories.isNotEmpty)
              SliverToBoxAdapter(child: _OnThisDay(entries: memories)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 120),
              sliver: feed.when(
                data: (entries) => entries.isEmpty
                    ? const SliverToBoxAdapter(
                        child: EmptyState(
                          icon: Icons.menu_book_outlined,
                          title: 'Nothing written yet',
                          message: 'Your entries, photos and voice notes will '
                              'appear here — and become the memory the '
                              'assistant draws on.',
                        ),
                      )
                    : SliverList.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => Gap.h12,
                        itemBuilder: (context, index) =>
                            _EntryCard(entry: entries[index]),
                      ),
                loading: () => SliverList.separated(
                  itemCount: 4,
                  separatorBuilder: (_, __) => Gap.h12,
                  itemBuilder: (_, __) =>
                      const SkeletonBox(height: 110, radius: Radii.lg),
                ),
                error: (error, _) => SliverToBoxAdapter(
                  child: Text('Could not load entries: $error'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnThisDay extends StatelessWidget {
  const _OnThisDay({required this.entries});

  final List<JournalEntry> entries;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 0),
        child: GlassCard(
          accent: AppColors.insights,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.history_rounded, size: 18),
                  Gap.w8,
                  Text('On this day', style: context.text.titleSmall),
                ],
              ),
              Gap.h12,
              for (final entry in entries.take(2))
                InkWell(
                  onTap: () => context.push(Routes.journalEntryFor(entry.id)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${DateTime.now().year - entry.createdAt.year} '
                          'year(s) ago · ${Fmt.shortDate(entry.createdAt)}',
                          style: context.text.labelSmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          entry.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _EntryCard extends ConsumerWidget {
  const _EntryCard({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Dismissible(
        key: ValueKey<String>(entry.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: Gap.xl),
          decoration: BoxDecoration(
            color: context.colors.errorContainer,
            borderRadius: Radii.cardRadius,
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            color: context.colors.onErrorContainer,
          ),
        ),
        confirmDismiss: (_) async => showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete this entry?'),
            content: const Text(
              'It will be removed from your journal and the timeline.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
        onDismissed: (_) =>
            ref.read(journalFeedProvider.notifier).delete(entry.id),
        child: GlassCard(
          onTap: () => context.push(Routes.journalEntryFor(entry.id)),
          semanticLabel: 'Journal entry: ${entry.displayTitle}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    Fmt.shortDate(entry.createdAt),
                    style: context.text.labelSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (entry.moodScore != null)
                    Text('${entry.moodScore}/10',
                        style: context.text.labelSmall),
                  if (entry.hasMedia) ...<Widget>[
                    Gap.w8,
                    const Icon(Icons.photo_outlined, size: 14),
                  ],
                  if (entry.isFavorite) ...<Widget>[
                    Gap.w8,
                    const Icon(Icons.star_rounded, size: 14),
                  ],
                ],
              ),
              Gap.h8,
              Text(entry.displayTitle, style: context.text.titleSmall),
              if (entry.analysis?.summary != null) ...<Widget>[
                Gap.h4,
                Text(
                  entry.analysis!.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (entry.tags.isNotEmpty) ...<Widget>[
                Gap.h12,
                Wrap(
                  spacing: Gap.xs,
                  runSpacing: Gap.xs,
                  children: <Widget>[
                    for (final tag in entry.tags.take(4))
                      Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}
