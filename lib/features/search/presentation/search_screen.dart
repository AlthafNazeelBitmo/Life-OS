import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_providers.dart';
import '../../../ai/models/ai_results.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/chat.dart';
import '../../../domain/repositories/search_repository.dart';

/// Search across every module.
///
/// Two layers, and the order matters: the lexical index answers instantly and
/// offline, and only if the user explicitly asks does the model get involved to
/// turn the hits into a sentence. Typing should never wait on a network call.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({this.initialQuery = '', super.key});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);

  Timer? _debounce;
  List<SearchHit> _hits = <SearchHit>[];
  Set<CitationSource> _sources = <CitationSource>{};
  AiAnswer? _answer;
  bool _searching = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _search(widget.initialQuery));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 220ms is long enough to skip most intermediate keystrokes and short enough
  /// that results feel like they are keeping up with typing.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 220),
      () => _search(value),
    );
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _hits = <SearchHit>[];
        _answer = null;
      });
      return;
    }

    setState(() => _searching = true);
    final result = await ref
        .read(searchRepositoryProvider)
        .search(query, sources: _sources);

    if (!mounted) return;
    setState(() {
      _hits = result.valueOrNull ?? <SearchHit>[];
      _searching = false;
      _answer = null;
    });
    unawaited(ref.read(searchRepositoryProvider).recordQuery(query));
  }

  Future<void> _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty) return;

    setState(() => _asking = true);
    final lifeContext =
        await ref.read(contextBuilderProvider).forQuestion(question);
    final result =
        await ref.read(aiServiceProvider).answerQuestion(question, lifeContext);

    if (!mounted) return;
    setState(() {
      _answer = result.valueOrNull;
      _asking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(_recentQueriesProvider).valueOrNull ?? const [];

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: SearchBar(
            controller: _controller,
            autoFocus: widget.initialQuery.isEmpty,
            hintText: 'Search everything',
            leading: const Icon(Icons.search_rounded),
            onChanged: _onChanged,
            onSubmitted: _search,
            elevation: const WidgetStatePropertyAll<double>(0),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 100),
          children: <Widget>[
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final source in CitationSource.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Gap.xs),
                      child: FilterChip(
                        label: Text(source.name),
                        selected: _sources.contains(source),
                        onSelected: (_) {
                          setState(() {
                            final next = Set<CitationSource>.from(_sources);
                            if (!next.remove(source)) next.add(source);
                            _sources = next;
                          });
                          _search(_controller.text);
                        },
                      ),
                    ),
                ],
              ),
            ),
            Gap.h12,
            if (_controller.text.trim().isNotEmpty)
              OutlinedButton.icon(
                onPressed: _asking ? null : _ask,
                icon: _asking
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(
                  _asking ? 'Reading your records…' : 'Ask this as a question',
                ),
              ),
            if (_answer != null) ...<Widget>[
              Gap.h16,
              GlassCard(
                accent: AppColors.insights,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_answer!.text, style: context.text.bodyMedium),
                    if (_answer!.citations.isNotEmpty) ...<Widget>[
                      Gap.h12,
                      Wrap(
                        spacing: Gap.xs,
                        children: <Widget>[
                          for (final citation in _answer!.citations.take(5))
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
              ),
            ],
            Gap.h16,
            if (_searching)
              const SkeletonBox(height: 70, radius: Radii.lg)
            else if (_hits.isEmpty && _controller.text.isNotEmpty)
              const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matches',
                message: 'Try a different word, or clear the filters.',
              )
            else if (_hits.isEmpty && recent.isNotEmpty) ...<Widget>[
              Text('Recent searches', style: context.text.titleSmall),
              Gap.h8,
              Wrap(
                spacing: Gap.xs,
                children: <Widget>[
                  for (final query in recent)
                    ActionChip(
                      label: Text(query),
                      onPressed: () {
                        _controller.text = query;
                        _search(query);
                      },
                    ),
                ],
              ),
            ] else
              for (final hit in _hits) _HitTile(hit: hit),
          ],
        ),
      ),
    );
  }
}

final FutureProvider<List<String>> _recentQueriesProvider =
    FutureProvider<List<String>>(
  (ref) async =>
      (await ref.watch(searchRepositoryProvider).recentQueries()).valueOrNull ??
      const <String>[],
);

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: GlassCard(
          padding: Insets.cardCompact,
          onTap: () => _open(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(_iconFor(hit.source), size: 14),
                  Gap.w8,
                  Text(
                    hit.source.name,
                    style: context.text.labelSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    Fmt.shortDate(hit.occurredAt),
                    style: context.text.labelSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Gap.h4,
              Text(hit.title, style: context.text.bodyMedium),
              if (hit.snippet.isNotEmpty)
                Text(
                  hit.snippet,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      );

  static IconData _iconFor(CitationSource source) => switch (source) {
        CitationSource.journal => Icons.menu_book_outlined,
        CitationSource.mood => Icons.mood_outlined,
        CitationSource.habit => Icons.repeat_rounded,
        CitationSource.goal => Icons.flag_outlined,
        CitationSource.task => Icons.check_circle_outline,
        CitationSource.event => Icons.event_outlined,
        CitationSource.transaction => Icons.payments_outlined,
        CitationSource.health => Icons.favorite_outline,
        CitationSource.person => Icons.person_outline,
      };

  void _open(BuildContext context) {
    switch (hit.source) {
      case CitationSource.journal:
        context.push(Routes.journalEntryFor(hit.id));
      case CitationSource.goal:
        context.push(Routes.goalDetailFor(hit.id));
      case CitationSource.habit:
        context.push(Routes.habitDetailFor(hit.id));
      case CitationSource.person:
        context.push(Routes.personDetailFor(hit.id));
      case CitationSource.task:
        context.push(Routes.tasks);
      case CitationSource.event:
        context.push(Routes.calendar);
      case CitationSource.transaction:
        context.push(Routes.money);
      case CitationSource.mood:
        context.push(Routes.mood);
      case CitationSource.health:
        context.push(Routes.health);
    }
  }
}
