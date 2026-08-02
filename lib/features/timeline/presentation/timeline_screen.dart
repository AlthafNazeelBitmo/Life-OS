import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/chip_strip.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/timeline_item.dart';

/// One infinite feed across every module.
///
/// Paged with a `before` cursor rather than an offset: new records are written
/// constantly, and an offset-based page would silently skip or repeat items as
/// the underlying set shifts under it.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  final ScrollController _scroll = ScrollController();
  final List<TimelineItem> _items = <TimelineItem>[];
  final Set<TimelineKind> _filter = <TimelineKind>{};

  DateTime _cursor = DateTime.now().add(const Duration(days: 1));
  bool _loading = false;
  bool _exhausted = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoad);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_maybeLoad)
      ..dispose();
    super.dispose();
  }

  void _maybeLoad() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 700) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (_exhausted && !reset)) return;
    setState(() => _loading = true);

    if (reset) {
      _items.clear();
      _cursor = DateTime.now().add(const Duration(days: 1));
      _exhausted = false;
    }

    final result = await ref.read(timelineRepositoryProvider).page(
          before: _cursor,
          kinds: _filter,
        );
    final page = result.valueOrNull ?? const <TimelineItem>[];

    if (!mounted) return;
    setState(() {
      _items.addAll(page);
      _loading = false;
      if (page.isEmpty) {
        _exhausted = true;
      } else {
        // Step one millisecond past the oldest item so the next page cannot
        // return the same record again.
        _cursor = page.last.occurredAt
            .subtract(const Duration(milliseconds: 1));
      }
    });
  }

  void _toggleFilter(TimelineKind kind) {
    setState(() {
      if (!_filter.remove(kind)) _filter.add(kind);
    });
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    // Group consecutive items by day so the feed reads as a diary, not a log.
    final grouped = <String, List<TimelineItem>>{};
    for (final item in _items) {
      grouped.putIfAbsent(Fmt.dayKey(item.occurredAt), () => <TimelineItem>[])
          .add(item);
    }
    final days = grouped.keys.toList();

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Timeline'),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(ChipStrip.heightFor(context)),
            child: ChipStrip(
              children: <Widget>[
                for (final kind in <TimelineKind>[
                  TimelineKind.journal,
                  TimelineKind.photo,
                  TimelineKind.mood,
                  TimelineKind.milestone,
                  TimelineKind.expense,
                  TimelineKind.event,
                  TimelineKind.task,
                ])
                  FilterChip(
                    label: Text(kind.name),
                    selected: _filter.contains(kind),
                    onSelected: (_) => _toggleFilter(kind),
                  ),
              ],
            ),
          ),
        ),
        body: _items.isEmpty && !_loading
            ? const EmptyState(
                icon: Icons.timeline_rounded,
                title: 'Nothing here yet',
                message: 'Journal entries, photos, milestones and moments will '
                    'collect here as you use LifeOS.',
              )
            : RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 120),
                  itemCount: days.length + 1,
                  itemBuilder: (context, index) {
                    if (index >= days.length) {
                      return Padding(
                        padding: const EdgeInsets.all(Gap.xl),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : Text(
                                  _exhausted ? 'That is the beginning.' : '',
                                  style: context.text.labelSmall?.copyWith(
                                    color: context.colors.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      );
                    }

                    final day = days[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Gap.md,
                          ),
                          child: Text(
                            Fmt.longDate(Fmt.parseDayKey(day)),
                            style: context.text.labelLarge?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final item in grouped[day]!)
                          _TimelineTile(item: item),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.item});

  final TimelineItem item;

  @override
  Widget build(BuildContext context) {
    final accent = item.colorValue == null
        ? AppColors.seed
        : Color(item.colorValue!);
    final image = item.imagePath;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The rail is what makes this read as a single thread rather than
            // a list of unrelated cards.
            Column(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 16),
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: context.colors.outlineVariant,
                  ),
                ),
              ],
            ),
            Gap.w12,
            Expanded(
              child: GlassCard(
                padding: Insets.cardCompact,
                child: Row(
                  children: <Widget>[
                    if (image != null && File(image).existsSync()) ...<Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        child: Image.file(
                          File(image),
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                      Gap.w12,
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.title,
                            style: context.text.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.subtitle.isNotEmpty)
                            Text(
                              item.subtitle,
                              style: context.text.labelSmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Text(
                      Fmt.time(item.occurredAt),
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
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
}
