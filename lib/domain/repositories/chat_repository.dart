import '../../core/error/result.dart';
import '../entities/chat.dart';

abstract interface class ChatRepository {
  Stream<List<ChatThread>> watchThreads();

  Stream<List<ChatMessage>> watchMessages(String threadId);

  Future<Result<ChatThread>> createThread({String? title});

  Future<Result<void>> renameThread(String threadId, String title);

  Future<Result<void>> deleteThread(String threadId);

  Future<Result<ChatMessage>> append(ChatMessage message);

  Future<Result<void>> update(ChatMessage message);

  /// Recent turns for the model's short-term memory, oldest first.
  Future<Result<List<ChatMessage>>> recent(String threadId, {int limit = 20});
}
