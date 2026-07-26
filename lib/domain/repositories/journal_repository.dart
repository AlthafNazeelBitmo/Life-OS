import '../../core/error/result.dart';
import '../entities/journal_entry.dart';

/// Reads are streams, writes return a [Result].
///
/// That split is deliberate and repeated across every repository: the UI binds
/// to a stream and re-renders whenever the database changes, so a write only
/// has to report success or failure — it never has to hand back the new list.
abstract interface class JournalRepository {
  Stream<List<JournalEntry>> watchEntries({int limit = 50, int offset = 0});

  Stream<List<JournalEntry>> watchByDay(String dayKey);

  Stream<JournalEntry?> watchEntry(String id);

  Future<Result<List<JournalEntry>>> page({
    required int limit,
    required int offset,
    String? query,
    List<String> tags = const <String>[],
    DateTime? from,
    DateTime? to,
  });

  Future<Result<JournalEntry?>> findById(String id);

  Future<Result<JournalEntry>> upsert(JournalEntry entry);

  /// Soft delete — the row is kept until the next sync so other devices learn
  /// about the deletion.
  Future<Result<void>> delete(String id);

  Future<Result<void>> restore(String id);

  Future<Result<void>> addAttachment(Attachment attachment);

  Future<Result<void>> removeAttachment(String attachmentId);

  /// Persists the AI's derived summary/emotions/themes for an entry.
  Future<Result<void>> saveAnalysis(String entryId, JournalAnalysis analysis);

  /// Consecutive days with at least one entry, ending today or yesterday.
  Future<Result<int>> currentStreak();

  Future<Result<List<String>>> allTags();

  /// Entries from the same calendar day in previous years.
  Future<Result<List<JournalEntry>>> onThisDay(DateTime date);

  Future<Result<int>> count();
}
