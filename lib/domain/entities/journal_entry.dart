import 'package:freezed_annotation/freezed_annotation.dart';

part 'journal_entry.freezed.dart';
part 'journal_entry.g.dart';

enum AttachmentKind { photo, video, audio, document }

@freezed
abstract class GeoPoint with _$GeoPoint {
  const factory GeoPoint({
    required double latitude,
    required double longitude,
    String? name,
  }) = _GeoPoint;

  factory GeoPoint.fromJson(Map<String, dynamic> json) =>
      _$GeoPointFromJson(json);
}

@freezed
abstract class Attachment with _$Attachment {
  const factory Attachment({
    required String id,
    required String entryId,
    required AttachmentKind kind,

    /// Path inside the app's documents directory. Media never leaves the device
    /// unless cloud sync is on.
    required String localPath,
    required DateTime createdAt,
    String? remoteUrl,
    String? caption,

    /// Speech-to-text result for voice notes; indexed by search.
    String? transcript,
    int? durationMs,
  }) = _Attachment;

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);
}

/// What the AI derived from an entry. Stored alongside the entry so it survives
/// offline and is never recomputed on every render.
@freezed
abstract class JournalAnalysis with _$JournalAnalysis {
  const factory JournalAnalysis({
    String? summary,
    @Default(<String>[]) List<String> emotions,
    @Default(<String>[]) List<String> themes,

    /// Notable things that happened — these become timeline moments.
    @Default(<String>[]) List<String> events,
    @Default(<String>[]) List<String> peopleMentioned,

    /// -1 (very negative) … 1 (very positive).
    double? sentiment,
    DateTime? analysedAt,

    /// Model that produced this, for provenance in the UI.
    String? model,
  }) = _JournalAnalysis;

  factory JournalAnalysis.fromJson(Map<String, dynamic> json) =>
      _$JournalAnalysisFromJson(json);
}

@freezed
abstract class JournalEntry with _$JournalEntry {
  const factory JournalEntry({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,

    /// `yyyy-MM-dd` bucket. One entry per day is the common case, but multiple
    /// are allowed — the day key is what streaks and "On This Day" use.
    required String dayKey,
    @Default('') String title,
    @Default('') String body,
    @Default(<String>[]) List<String> tags,

    /// Person ids referenced by this entry.
    @Default(<String>[]) List<String> peopleIds,
    @Default(<Attachment>[]) List<Attachment> attachments,
    GeoPoint? location,
    String? weather,

    /// 1–10 quick mood rating captured with the entry.
    int? moodScore,
    JournalAnalysis? analysis,
    @Default(false) bool isFavorite,
    DateTime? deletedAt,
  }) = _JournalEntry;

  const JournalEntry._();

  factory JournalEntry.fromJson(Map<String, dynamic> json) =>
      _$JournalEntryFromJson(json);

  bool get isDeleted => deletedAt != null;

  int get wordCount =>
      body.trim().isEmpty ? 0 : body.trim().split(RegExp(r'\s+')).length;

  bool get hasMedia => attachments.isNotEmpty;

  /// Title if the user wrote one, otherwise the opening line of the body.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = body.trim().split('\n').first.trim();
    if (firstLine.isEmpty) return 'Untitled entry';
    return firstLine.length <= 60 ? firstLine : '${firstLine.substring(0, 57)}…';
  }

  /// Everything searchable about this entry, including voice transcripts.
  String get searchableText => <String>[
        title,
        body,
        ...tags,
        ...attachments.map((a) => a.transcript ?? ''),
        ...attachments.map((a) => a.caption ?? ''),
        analysis?.summary ?? '',
        location?.name ?? '',
      ].where((s) => s.isNotEmpty).join(' ');
}
