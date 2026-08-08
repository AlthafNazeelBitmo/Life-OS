import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/error/result.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/journal_entry.dart';

/// Paged journal feed.
///
/// Paged rather than fully streamed: a journal grows without bound, and loading
/// several years of entries to show the last ten is the kind of thing that
/// makes an app feel slow after a year of use.
class JournalFeedController extends AsyncNotifier<List<JournalEntry>> {
  static const int _pageSize = 20;

  int _offset = 0;
  bool _hasMore = true;
  String _query = '';

  @override
  Future<List<JournalEntry>> build() async {
    _offset = 0;
    _hasMore = true;
    // Re-runs whenever the journal table changes, which keeps the first page
    // live while later pages stay lazily loaded.
    ref.watch(journalRepositoryProvider);
    return _fetch(reset: true);
  }

  Future<List<JournalEntry>> _fetch({required bool reset}) async {
    final result = await ref.read(journalRepositoryProvider).page(
          limit: _pageSize,
          offset: reset ? 0 : _offset,
          query: _query.isEmpty ? null : _query,
        );
    final entries = result.valueOrNull ?? const <JournalEntry>[];
    _hasMore = entries.length == _pageSize;
    _offset = (reset ? 0 : _offset) + entries.length;
    return entries;
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;
    final current = state.valueOrNull ?? const <JournalEntry>[];
    final next = await _fetch(reset: false);
    state = AsyncData<List<JournalEntry>>(<JournalEntry>[...current, ...next]);
  }

  Future<void> search(String query) async {
    _query = query.trim();
    state = const AsyncLoading<List<JournalEntry>>().copyWithPrevious(state);
    state = AsyncData<List<JournalEntry>>(await _fetch(reset: true));
  }

  Future<void> delete(String id) async {
    await ref.read(journalRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }
}

final AsyncNotifierProvider<JournalFeedController, List<JournalEntry>>
    journalFeedProvider =
    AsyncNotifierProvider<JournalFeedController, List<JournalEntry>>(
  JournalFeedController.new,
);

final StreamProviderFamily<JournalEntry?, String> journalEntryProvider =
    StreamProvider.family<JournalEntry?, String>(
  (ref, id) => ref.watch(journalRepositoryProvider).watchEntry(id),
);

final FutureProvider<int> journalStreakProvider = FutureProvider<int>(
  (ref) async =>
      (await ref.watch(journalRepositoryProvider).currentStreak()).valueOrNull ??
      0,
);

/// "On this day" — the same date in previous years.
final FutureProvider<List<JournalEntry>> onThisDayProvider =
    FutureProvider<List<JournalEntry>>(
  (ref) async =>
      (await ref.watch(journalRepositoryProvider).onThisDay(DateTime.now()))
          .valueOrNull ??
      const <JournalEntry>[],
);

/// Saves an entry and enriches it in the background.
///
/// The write returns as soon as the text is on disk; analysis is fire-and-
/// forget, because the user should never wait on a model to close a journal
/// entry — and if it fails, the entry is still theirs.
class JournalComposer extends Notifier<bool> {
  @override
  bool build() => false;

  Future<Result<JournalEntry>> save(JournalEntry draft) async {
    state = true;
    final entry = draft.id.isEmpty
        ? draft.copyWith(
            id: newId(),
            dayKey: Fmt.dayKey(draft.createdAt),
          )
        : draft;

    final result = await ref.read(journalRepositoryProvider).upsert(entry);
    state = false;

    if (result.isOk) {
      // Not awaited on purpose: the entry is already saved, and a slow or
      // failing model must never hold up closing the editor.
      unawaited(
        _analyse(entry).catchError(
          (Object error) =>
              AppLogger.warn('journal', 'Background analysis failed', error),
        ),
      );
      ref.invalidate(journalFeedProvider);
    }
    return result;
  }

  Future<void> _analyse(JournalEntry entry) async {
    if (entry.body.trim().length < 40) return;

    final ai = ref.read(aiServiceProvider);
    final summary = await ai.summarize(entry.body, maxSentences: 2);
    final mood = await ai.analyzeMood(entry.body);

    final analysis = JournalAnalysis(
      summary: summary.valueOrNull?.summary,
      emotions: mood.valueOrNull?.emotions ?? const <String>[],
      themes: mood.valueOrNull?.themes ?? const <String>[],
      events: mood.valueOrNull?.events ?? const <String>[],
      peopleMentioned: mood.valueOrNull?.people ?? const <String>[],
      sentiment: mood.valueOrNull?.sentiment,
      analysedAt: DateTime.now(),
      model: ai.model,
    );

    final saved = await ref
        .read(journalRepositoryProvider)
        .saveAnalysis(entry.id, analysis);
    if (saved.isErr) {
      AppLogger.warn('journal', 'Could not store analysis for ${entry.id}');
    }
    ref.invalidate(journalFeedProvider);
  }
}

final NotifierProvider<JournalComposer, bool> journalComposerProvider =
    NotifierProvider<JournalComposer, bool>(JournalComposer.new);
