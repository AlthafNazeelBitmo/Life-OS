import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/utils/ids.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/chat.dart';

@immutable
class ChatState {
  const ChatState({
    this.threadId,
    this.messages = const <ChatMessage>[],
    this.isThinking = false,
    this.streamingText,
    this.error,
  });

  final String? threadId;
  final List<ChatMessage> messages;
  final bool isThinking;

  /// Partial assistant reply while tokens are still arriving.
  final String? streamingText;
  final String? error;

  ChatState copyWith({
    String? threadId,
    List<ChatMessage>? messages,
    bool? isThinking,
    String? streamingText,
    String? error,
  }) =>
      ChatState(
        threadId: threadId ?? this.threadId,
        messages: messages ?? this.messages,
        isThinking: isThinking ?? this.isThinking,
        streamingText: streamingText,
        error: error,
      );
}

/// Drives one conversation.
///
/// The grounding step is not optional: every question goes through the context
/// builder first, and the answer is stored with the citations it resolved. A
/// reply the model could not ground is shown as such rather than dressed up.
class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> openThread({String? threadId}) async {
    final repository = ref.read(chatRepositoryProvider);

    if (threadId != null) {
      final messages = await repository.recent(threadId, limit: 100);
      state = ChatState(
        threadId: threadId,
        messages: messages.valueOrNull ?? const <ChatMessage>[],
      );
      return;
    }

    final created = await repository.createThread();
    state = ChatState(threadId: created.valueOrNull?.id);
  }

  Future<void> send(String text) async {
    final question = text.trim();
    if (question.isEmpty || state.isThinking) return;

    if (state.threadId == null) await openThread();
    final threadId = state.threadId;
    if (threadId == null) return;

    final repository = ref.read(chatRepositoryProvider);
    final userMessage = ChatMessage(
      id: newId(),
      threadId: threadId,
      role: ChatRole.user,
      content: question,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      messages: <ChatMessage>[...state.messages, userMessage],
      isThinking: true,
    );
    await repository.append(userMessage);

    // Retrieval before generation — see ContextBuilder.forQuestion.
    final context = await ref.read(contextBuilderProvider).forQuestion(question);

    // The last few turns give the model enough continuity for follow-ups like
    // "and last month?" without resending the whole history every time.
    final history = state.messages
        .where((message) => message.isUser)
        .map((message) => message.content)
        .toList();
    final recentHistory =
        history.length <= 6 ? history : history.sublist(history.length - 6);

    final result = await ref.read(aiServiceProvider).answerQuestion(
          question,
          context,
          conversationHistory: recentHistory,
        );

    final reply = result.fold(
      (answer) => ChatMessage(
        id: newId(),
        threadId: threadId,
        role: ChatRole.assistant,
        content: answer.text,
        createdAt: DateTime.now(),
        citations: answer.citations,
        model: answer.model,
      ),
      (failure) => ChatMessage(
        id: newId(),
        threadId: threadId,
        role: ChatRole.assistant,
        content: failure.message,
        createdAt: DateTime.now(),
        error: failure.message,
      ),
    );

    state = state.copyWith(
      messages: <ChatMessage>[...state.messages, reply],
      isThinking: false,
      error: reply.error,
    );
    await repository.append(reply);

    // First question makes a better thread title than "New conversation".
    if (state.messages.length == 2) {
      await repository.renameThread(
        threadId,
        question.length <= 48 ? question : '${question.substring(0, 45)}…',
      );
    }
  }

  Future<void> clear() async {
    state = const ChatState();
    await openThread();
  }
}

final NotifierProvider<ChatController, ChatState> chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

/// Prompt starters shown on an empty conversation. Phrased as the questions
/// LifeOS can actually answer from the user's own data.
const List<String> chatSuggestions = <String>[
  'How has my mood changed over the last month?',
  'What habits line up with my best days?',
  'Where did most of my money go last month?',
  'Plan my week around what is already scheduled.',
  'What have I been putting off?',
];
