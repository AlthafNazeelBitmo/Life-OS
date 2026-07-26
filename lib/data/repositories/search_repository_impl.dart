import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../domain/entities/chat.dart';
import '../../domain/repositories/search_repository.dart';
import '../local/app_database.dart';
import '../local/search_indexer.dart';
import '../mappers/mappers.dart';

/// Lexical search over the denormalised `search_docs` index.
///
/// Deliberately not a vector store: it is instant, works with no network and no
/// model, and returns exact matches — which is what "what did I write about
/// Japan?" actually needs. Natural-language questions are layered on top by the
/// AI service, which uses these hits as its grounding set.
class SearchRepositoryImpl implements SearchRepository {
  SearchRepositoryImpl(this._db) : _indexer = SearchIndexer(_db);

  final AppDatabase _db;
  final SearchIndexer _indexer;

  @override
  Future<Result<List<SearchHit>>> search(
    String query, {
    Set<CitationSource> sources = const <CitationSource>{},
    DateTime? from,
    DateTime? to,
    int limit = 50,
  }) =>
      Result.guard(() async {
        final terms = query
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((t) => t.length > 1)
            .toList();
        if (terms.isEmpty) return const <SearchHit>[];

        final select = _db.select(_db.searchDocs);
        // AND across terms: adding a word should narrow the result set.
        for (final term in terms) {
          select.where((t) => t.body.like('%$term%'));
        }
        if (sources.isNotEmpty) {
          select.where((t) => t.source.isInValues(sources.toList()));
        }
        if (from != null) {
          select.where((t) => t.occurredAt.isBiggerOrEqualValue(from));
        }
        if (to != null) {
          select.where((t) => t.occurredAt.isSmallerOrEqualValue(to));
        }
        select
          ..orderBy(<OrderClauseGenerator<$SearchDocsTable>>[
            (t) => OrderingTerm.desc(t.occurredAt),
          ])
          ..limit(limit * 2);

        final rows = await select.get();
        final hits = rows.map((row) {
          final body = row.body;
          var score = 0.0;
          for (final term in terms) {
            if (row.title.toLowerCase().contains(term)) score += 3;
            score += term.allMatches(body).length.clamp(0, 5);
          }
          // Recency is a mild tiebreaker, not a ranking: an exact hit from two
          // years ago should still beat a weak match from yesterday.
          final ageDays = DateTime.now().difference(row.occurredAt).inDays;
          score += (365 - ageDays.clamp(0, 365)) / 365;

          return SearchHit(
            id: row.sourceId,
            source: row.source,
            title: row.title,
            snippet: _snippet(body, terms.first),
            occurredAt: row.occurredAt,
            score: score,
            imagePath: row.imagePath,
          );
        }).toList()
          ..sort((a, b) => b.score.compareTo(a.score));

        return hits.take(limit).toList();
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  String _snippet(String body, String term) {
    final index = body.indexOf(term);
    if (index < 0) {
      return body.length <= 140 ? body : '${body.substring(0, 137)}…';
    }
    final start = (index - 50).clamp(0, body.length);
    final end = (index + 90).clamp(0, body.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < body.length ? '…' : '';
    return '$prefix${body.substring(start, end)}$suffix';
  }

  @override
  Future<Result<List<String>>> recentQueries({int limit = 8}) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.recentQueries)
              ..orderBy(<OrderClauseGenerator<$RecentQueriesTable>>[
                (t) => OrderingTerm.desc(t.searchedAt),
              ])
              ..limit(limit))
            .get();
        return rows.map((r) => r.query).toList();
      });

  @override
  Future<Result<void>> recordQuery(String query) => Result.guard(() async {
        final trimmed = query.trim();
        if (trimmed.isEmpty) return;
        await _db.into(_db.recentQueries).insertOnConflictUpdate(
              RecentQueriesCompanion.insert(
                query: trimmed,
                searchedAt: DateTime.now(),
              ),
            );
      });

  @override
  Future<Result<void>> reindex() => Result.guard(() async {
        await _db.transaction(() async {
          await _db.delete(_db.searchDocs).go();

          for (final row in await (_db.select(_db.journalEntries)
                ..where((t) => t.deletedAt.isNull()))
              .get()) {
            final entry = row.toEntity();
            await _indexer.index(
              source: CitationSource.journal,
              sourceId: entry.id,
              title: entry.displayTitle,
              body: entry.searchableText,
              occurredAt: entry.createdAt,
            );
          }
          for (final row in await _db.select(_db.tasks).get()) {
            await _indexer.index(
              source: CitationSource.task,
              sourceId: row.id,
              title: row.title,
              body: row.notes,
              occurredAt: row.dueAt ?? row.createdAt,
            );
          }
          for (final row in await _db.select(_db.goals).get()) {
            await _indexer.index(
              source: CitationSource.goal,
              sourceId: row.id,
              title: row.title,
              body: row.description,
              occurredAt: row.createdAt,
            );
          }
          for (final row in await (_db.select(_db.moneyTransactions)
                ..where((t) => t.deletedAt.isNull()))
              .get()) {
            await _indexer.index(
              source: CitationSource.transaction,
              sourceId: row.id,
              title: row.merchant,
              body: '${row.note} ${row.receiptText ?? ''}',
              occurredAt: row.occurredAt,
            );
          }
          for (final row in await (_db.select(_db.calendarEvents)
                ..where((t) => t.deletedAt.isNull()))
              .get()) {
            await _indexer.index(
              source: CitationSource.event,
              sourceId: row.id,
              title: row.title,
              body: '${row.description} ${row.location}',
              occurredAt: row.startsAt,
            );
          }
          for (final row in await _db.select(_db.people).get()) {
            await _indexer.index(
              source: CitationSource.person,
              sourceId: row.id,
              title: row.name,
              body: '${row.relation} ${row.notes} ${row.details.join(' ')}',
              occurredAt: row.lastInteractionAt ?? row.createdAt,
            );
          }
        });
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));
}
