import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat.freezed.dart';
part 'chat.g.dart';

enum ChatRole { user, assistant, system }

/// Where a source lives in the app, so a citation can deep-link to it.
enum CitationSource {
  journal,
  mood,
  habit,
  goal,
  task,
  event,
  transaction,
  health,
  person,
}

/// A pointer from an AI statement back to the user's own record.
///
/// Citations are the mechanism that keeps the assistant honest: the prompt only
/// ever sees chunks that carry an id, and any claim without a matching id is
/// flagged rather than shown as fact.
@freezed
abstract class Citation with _$Citation {
  const factory Citation({
    required String id,
    required CitationSource source,
    required String label,
    DateTime? occurredAt,

    /// The exact text handed to the model, kept for "show me why".
    String? excerpt,
  }) = _Citation;

  factory Citation.fromJson(Map<String, dynamic> json) =>
      _$CitationFromJson(json);
}

@freezed
abstract class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String threadId,
    required ChatRole role,
    required String content,
    required DateTime createdAt,
    @Default(<Citation>[]) List<Citation> citations,

    /// Set while a streamed reply is still arriving.
    @Default(false) bool isStreaming,
    String? error,
    String? model,
    int? promptTokens,
    int? completionTokens,
  }) = _ChatMessage;

  const ChatMessage._();

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);

  bool get isUser => role == ChatRole.user;
  bool get hasCitations => citations.isNotEmpty;
}

@freezed
abstract class ChatThread with _$ChatThread {
  const factory ChatThread({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default('New conversation') String title,
    @Default(false) bool pinned,
  }) = _ChatThread;

  factory ChatThread.fromJson(Map<String, dynamic> json) =>
      _$ChatThreadFromJson(json);
}
