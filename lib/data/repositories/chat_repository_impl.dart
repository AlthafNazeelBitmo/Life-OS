import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/chat.dart';
import '../../domain/repositories/chat_repository.dart';
import '../local/app_database.dart';
import '../mappers/mappers.dart';

class ChatRepositoryImpl implements ChatRepository {
  const ChatRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Stream<List<ChatThread>> watchThreads() => (_db.select(_db.chatThreads)
        ..orderBy(<OrderClauseGenerator<$ChatThreadsTable>>[
          (t) => OrderingTerm.desc(t.pinned),
          (t) => OrderingTerm.desc(t.updatedAt),
        ]))
      .watch()
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ChatMessage>> watchMessages(String threadId) =>
      (_db.select(_db.chatMessages)
            ..where((t) => t.threadId.equals(threadId))
            ..orderBy(<OrderClauseGenerator<$ChatMessagesTable>>[
              (t) => OrderingTerm.asc(t.createdAt),
            ]))
          .watch()
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<ChatThread>> createThread({String? title}) =>
      Result.guard(() async {
        final now = DateTime.now();
        final thread = ChatThread(
          id: newId(),
          createdAt: now,
          updatedAt: now,
          title: title ?? 'New conversation',
        );
        await _db.into(_db.chatThreads).insert(
              ChatThreadsCompanion.insert(
                id: thread.id,
                createdAt: thread.createdAt,
                updatedAt: thread.updatedAt,
                title: Value(thread.title),
              ),
            );
        return thread;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> renameThread(String threadId, String title) =>
      Result.guard(() async {
        await (_db.update(_db.chatThreads)..where((t) => t.id.equals(threadId)))
            .write(ChatThreadsCompanion(title: Value(title)));
      });

  @override
  Future<Result<void>> deleteThread(String threadId) => Result.guard(() async {
        await (_db.delete(_db.chatThreads)..where((t) => t.id.equals(threadId)))
            .go();
      });

  @override
  Future<Result<ChatMessage>> append(ChatMessage message) =>
      Result.guard(() async {
        await _db.transaction(() async {
          await _db
              .into(_db.chatMessages)
              .insertOnConflictUpdate(message.toCompanion());
          // Threads sort by recency, so every message touches the parent.
          await (_db.update(_db.chatThreads)
                ..where((t) => t.id.equals(message.threadId)))
              .write(ChatThreadsCompanion(updatedAt: Value(message.createdAt)));
        });
        return message;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> update(ChatMessage message) => Result.guard(() async {
        await _db
            .into(_db.chatMessages)
            .insertOnConflictUpdate(message.toCompanion());
      });

  @override
  Future<Result<List<ChatMessage>>> recent(
    String threadId, {
    int limit = 20,
  }) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.chatMessages)
              ..where((t) => t.threadId.equals(threadId))
              ..orderBy(<OrderClauseGenerator<$ChatMessagesTable>>[
                (t) => OrderingTerm.desc(t.createdAt),
              ])
              ..limit(limit))
            .get();
        // Fetched newest-first for the LIMIT, handed back oldest-first because
        // that is the order a model expects its history in.
        return rows.reversed.map((r) => r.toEntity()).toList();
      });
}
