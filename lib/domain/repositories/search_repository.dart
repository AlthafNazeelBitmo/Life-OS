import '../../core/error/result.dart';
import '../entities/chat.dart';

/// One hit in the unified search index.
class SearchHit {
  const SearchHit({
    required this.id,
    required this.source,
    required this.title,
    required this.snippet,
    required this.occurredAt,
    this.score = 0,
    this.imagePath,
  });

  final String id;
  final CitationSource source;
  final String title;

  /// Matched text with the query terms left in place; the UI highlights them.
  final String snippet;
  final DateTime occurredAt;

  /// Relevance, higher is better.
  final double score;
  final String? imagePath;
}

/// Search spans every module.
///
/// Two tiers: [search] is a fast lexical pass over the SQLite FTS index and
/// always works offline; [ask] adds the model on top, which turns
/// "when did I last meet Alex?" into a filter plus a written answer.
abstract interface class SearchRepository {
  Future<Result<List<SearchHit>>> search(
    String query, {
    Set<CitationSource> sources = const <CitationSource>{},
    DateTime? from,
    DateTime? to,
    int limit = 50,
  });

  /// Recent queries, for the empty state.
  Future<Result<List<String>>> recentQueries({int limit = 8});

  Future<Result<void>> recordQuery(String query);

  /// Rebuilds the FTS index. Called after a restore or a schema migration.
  Future<Result<void>> reindex();
}
