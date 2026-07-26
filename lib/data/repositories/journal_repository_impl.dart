import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/extensions/date_time_x.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/chat.dart' show CitationSource;
import '../../domain/entities/journal_entry.dart';
import '../../domain/repositories/journal_repository.dart';
import '../local/app_database.dart';
import '../local/search_indexer.dart';
import '../mappers/mappers.dart';
import '../remote/sync_queue_writer.dart';

class JournalRepositoryImpl implements JournalRepository {
  JournalRepositoryImpl(this._db, this._sync) : _indexer = SearchIndexer(_db);

  final AppDatabase _db;
  final SyncQueueWriter _sync;
  final SearchIndexer _indexer;

  /// Attachments are a separate table but conceptually part of an entry, so
  /// every read joins them back on. The join is by entry id and bounded by the
  /// page size, which keeps it cheap.
  Future<List<JournalEntry>> _hydrate(List<JournalEntryRow> rows) async {
    if (rows.isEmpty) return const <JournalEntry>[];
    final ids = rows.map((row) => row.id).toList();
    final attachmentRows = await (_db.select(_db.attachments)
          ..where((t) => t.entryId.isIn(ids)))
        .get();

    final byEntry = <String, List<Attachment>>{};
    for (final row in attachmentRows) {
      byEntry.putIfAbsent(row.entryId, () => <Attachment>[]).add(row.toEntity());
    }
    return rows
        .map((row) => row.toEntity(
              attachments: byEntry[row.id] ?? const <Attachment>[],
            ))
        .toList();
  }

  @override
  Stream<List<JournalEntry>> watchEntries({int limit = 50, int offset = 0}) {
    final query = _db.select(_db.journalEntries)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<$JournalEntriesTable>>[
        (t) => OrderingTerm.desc(t.createdAt),
      ])
      ..limit(limit, offset: offset);
    return query.watch().asyncMap(_hydrate);
  }

  @override
  Stream<List<JournalEntry>> watchByDay(String dayKey) {
    final query = _db.select(_db.journalEntries)
      ..where((t) => t.dayKey.equals(dayKey) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<$JournalEntriesTable>>[
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    return query.watch().asyncMap(_hydrate);
  }

  @override
  Stream<JournalEntry?> watchEntry(String id) {
    final query = _db.select(_db.journalEntries)..where((t) => t.id.equals(id));
    return query.watch().asyncMap((rows) async {
      if (rows.isEmpty) return null;
      final hydrated = await _hydrate(rows);
      return hydrated.first;
    });
  }

  @override
  Future<Result<List<JournalEntry>>> page({
    required int limit,
    required int offset,
    String? query,
    List<String> tags = const <String>[],
    DateTime? from,
    DateTime? to,
  }) =>
      Result.guard(() async {
        final select = _db.select(_db.journalEntries)
          ..where((t) => t.deletedAt.isNull());

        if (query != null && query.trim().isNotEmpty) {
          final needle = '%${query.trim().toLowerCase()}%';
          select.where(
            (t) => t.title.lower().like(needle) | t.body.lower().like(needle),
          );
        }
        if (from != null) {
          select.where((t) => t.createdAt.isBiggerOrEqualValue(from));
        }
        if (to != null) {
          select.where((t) => t.createdAt.isSmallerOrEqualValue(to));
        }

        select
          ..orderBy(<OrderClauseGenerator<$JournalEntriesTable>>[
            (t) => OrderingTerm.desc(t.createdAt),
          ])
          ..limit(limit, offset: offset);

        final entries = await _hydrate(await select.get());
        if (tags.isEmpty) return entries;
        // Tags live in a JSON column; filtering them in Dart keeps the schema
        // simple and the lists are short enough that it costs nothing.
        return entries
            .where((entry) => tags.every(entry.tags.contains))
            .toList();
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<JournalEntry?>> findById(String id) => Result.guard(() async {
        final row = await (_db.select(_db.journalEntries)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (row == null) return null;
        return (await _hydrate(<JournalEntryRow>[row])).first;
      });

  @override
  Future<Result<JournalEntry>> upsert(JournalEntry entry) =>
      Result.guard(() async {
        final saved = entry.copyWith(updatedAt: DateTime.now());
        await _db.transaction(() async {
          await _db
              .into(_db.journalEntries)
              .insertOnConflictUpdate(saved.toCompanion());

          // Replace-all is correct here: attachments are always edited as part
          // of the entry, never independently.
          await (_db.delete(_db.attachments)
                ..where((t) => t.entryId.equals(saved.id)))
              .go();
          for (final attachment in saved.attachments) {
            await _db
                .into(_db.attachments)
                .insertOnConflictUpdate(attachment.toCompanion());
          }

          await _indexer.index(
            source: CitationSource.journal,
            sourceId: saved.id,
            title: saved.displayTitle,
            body: saved.searchableText,
            occurredAt: saved.createdAt,
            imagePath: saved.attachments
                .where((a) => a.kind == AttachmentKind.photo)
                .map((a) => a.localPath)
                .firstOrNull,
          );
          await _sync.enqueue(
            entity: 'journal_entries',
            entityId: saved.id,
            operation: SyncOperation.upsert,
            payload: saved.toJson(),
          );
        });
        return saved;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> delete(String id) => Result.guard(() async {
        await _db.transaction(() async {
          await (_db.update(_db.journalEntries)..where((t) => t.id.equals(id)))
              .write(JournalEntriesCompanion(deletedAt: Value(DateTime.now())));
          await _indexer.remove(CitationSource.journal, id);
          await _sync.enqueue(
            entity: 'journal_entries',
            entityId: id,
            operation: SyncOperation.delete,
            payload: const <String, dynamic>{},
          );
        });
      });

  @override
  Future<Result<void>> restore(String id) => Result.guard(() async {
        await (_db.update(_db.journalEntries)..where((t) => t.id.equals(id)))
            .write(const JournalEntriesCompanion(deletedAt: Value<DateTime?>(null)));
      });

  @override
  Future<Result<void>> addAttachment(Attachment attachment) =>
      Result.guard(() async {
        await _db
            .into(_db.attachments)
            .insertOnConflictUpdate(attachment.toCompanion());
      });

  @override
  Future<Result<void>> removeAttachment(String attachmentId) =>
      Result.guard(() async {
        await (_db.delete(_db.attachments)
              ..where((t) => t.id.equals(attachmentId)))
            .go();
      });

  @override
  Future<Result<void>> saveAnalysis(
    String entryId,
    JournalAnalysis analysis,
  ) =>
      Result.guard(() async {
        await (_db.update(_db.journalEntries)..where((t) => t.id.equals(entryId)))
            .write(JournalEntriesCompanion(analysis: Value(analysis)));
      });

  @override
  Future<Result<int>> currentStreak() => Result.guard(() async {
        final rows = await _db
            .customSelect(
              'SELECT DISTINCT day_key FROM journal_entries '
              'WHERE deleted_at IS NULL ORDER BY day_key DESC LIMIT 400',
              readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
                _db.journalEntries,
              },
            )
            .get();
        final days = rows.map((row) => row.read<String>('day_key')).toSet();
        if (days.isEmpty) return 0;

        // A streak stays alive until the end of today: writing yesterday and
        // not yet today should still read as an active streak.
        var cursor = DateTime.now().startOfDay;
        if (!days.contains(Fmt.dayKey(cursor))) {
          cursor = cursor.subtract(const Duration(days: 1));
          if (!days.contains(Fmt.dayKey(cursor))) return 0;
        }

        var streak = 0;
        while (days.contains(Fmt.dayKey(cursor))) {
          streak++;
          cursor = cursor.subtract(const Duration(days: 1));
        }
        return streak;
      });

  @override
  Future<Result<List<String>>> allTags() => Result.guard(() async {
        final rows = await (_db.select(_db.journalEntries)
              ..where((t) => t.deletedAt.isNull()))
            .get();
        final tags = <String>{};
        for (final row in rows) {
          tags.addAll(row.tags);
        }
        final sorted = tags.toList()..sort();
        return sorted;
      });

  @override
  Future<Result<List<JournalEntry>>> onThisDay(DateTime date) =>
      Result.guard(() async {
        final suffix =
            '-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final currentYear = date.year.toString().padLeft(4, '0');
        final rows = await (_db.select(_db.journalEntries)
              ..where(
                (t) =>
                    t.dayKey.like('%$suffix') &
                    t.dayKey.like('$currentYear%').not() &
                    t.deletedAt.isNull(),
              )
              ..orderBy(<OrderClauseGenerator<$JournalEntriesTable>>[
                (t) => OrderingTerm.desc(t.createdAt),
              ]))
            .get();
        return _hydrate(rows);
      });

  @override
  Future<Result<int>> count() => Result.guard(() async {
        final row = await _db.customSelect(
          'SELECT COUNT(*) AS c FROM journal_entries WHERE deleted_at IS NULL',
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
            _db.journalEntries,
          },
        ).getSingle();
        return row.read<int>('c');
      });
}
