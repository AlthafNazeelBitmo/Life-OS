import 'package:drift/drift.dart';

import '../../domain/entities/chat.dart';
import 'app_database.dart';

/// Keeps the cross-module search index in step with the module tables.
///
/// Every repository calls [index] inside the same transaction as its write, so
/// the index can never describe a record that no longer exists. Bodies are
/// stored lower-cased because the lexical matcher is case-insensitive and doing
/// it once on write beats doing it on every keystroke.
class SearchIndexer {
  const SearchIndexer(this._db);

  final AppDatabase _db;

  static String docId(CitationSource source, String sourceId) =>
      '${source.name}:$sourceId';

  Future<void> index({
    required CitationSource source,
    required String sourceId,
    required String title,
    required String body,
    required DateTime occurredAt,
    String? imagePath,
  }) =>
      _db.into(_db.searchDocs).insertOnConflictUpdate(
            SearchDocsCompanion.insert(
              id: docId(source, sourceId),
              source: source,
              sourceId: sourceId,
              title: title,
              body: '$title\n$body'.toLowerCase(),
              occurredAt: occurredAt,
              imagePath: Value(imagePath),
            ),
          );

  Future<void> remove(CitationSource source, String sourceId) =>
      (_db.delete(_db.searchDocs)
            ..where((t) => t.id.equals(docId(source, sourceId))))
          .go();

  Future<void> clearSource(CitationSource source) =>
      (_db.delete(_db.searchDocs)..where((t) => t.source.equalsValue(source)))
          .go();
}
