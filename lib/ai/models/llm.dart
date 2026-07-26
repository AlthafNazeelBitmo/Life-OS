import 'package:flutter/foundation.dart';

enum LlmRole { system, user, assistant }

@immutable
class LlmMessage {
  const LlmMessage(this.role, this.content);

  const LlmMessage.system(this.content) : role = LlmRole.system;
  const LlmMessage.user(this.content) : role = LlmRole.user;
  const LlmMessage.assistant(this.content) : role = LlmRole.assistant;

  final LlmRole role;
  final String content;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'role': role.name, 'content': content};
}

/// Whether the caller wants prose or a machine-readable object back.
enum LlmResponseFormat { text, json }

@immutable
class LlmRequest {
  const LlmRequest({
    required this.messages,
    this.model,
    this.temperature = 0.4,
    this.maxTokens = 1200,
    this.format = LlmResponseFormat.text,
    this.timeout = const Duration(seconds: 45),
  });

  final List<LlmMessage> messages;

  /// Null means "the provider's configured default".
  final String? model;
  final double temperature;
  final int maxTokens;
  final LlmResponseFormat format;
  final Duration timeout;

  /// System messages are separated because providers disagree about where they
  /// go — a top-level field for Anthropic and Gemini, a message for OpenAI.
  String get systemPrompt => messages
      .where((m) => m.role == LlmRole.system)
      .map((m) => m.content)
      .join('\n\n');

  List<LlmMessage> get conversation =>
      messages.where((m) => m.role != LlmRole.system).toList();

  LlmRequest copyWith({
    List<LlmMessage>? messages,
    String? model,
    double? temperature,
    int? maxTokens,
    LlmResponseFormat? format,
  }) =>
      LlmRequest(
        messages: messages ?? this.messages,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        format: format ?? this.format,
        timeout: timeout,
      );
}

@immutable
class LlmCompletion {
  const LlmCompletion({
    required this.text,
    required this.model,
    this.promptTokens,
    this.completionTokens,
    this.finishReason,
  });

  final String text;
  final String model;
  final int? promptTokens;
  final int? completionTokens;
  final String? finishReason;

  /// True when the model ran out of room; callers can retry with a smaller
  /// context rather than showing a truncated answer as if it were complete.
  bool get wasTruncated => finishReason == 'length' || finishReason == 'max_tokens';
}
