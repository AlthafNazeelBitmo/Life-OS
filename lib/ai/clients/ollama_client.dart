import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/failures.dart';
import '../llm_client.dart';
import '../models/llm.dart';

/// Talks to a local Ollama server.
///
/// The privacy story is the reason this exists: a capable model with the same
/// guarantee as the offline provider — nothing leaves the user's own network.
class OllamaClient with LlmHttpErrors implements LlmClient {
  OllamaClient({
    required this.model,
    required String baseUrl,
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;

  final http.Client _http;
  final String _baseUrl;

  @override
  final String model;

  @override
  String get providerId => 'ollama';

  Map<String, dynamic> _body(LlmRequest request, {required bool stream}) =>
      <String, dynamic>{
        'model': request.model ?? model,
        'messages': request.messages.map((m) => m.toJson()).toList(),
        'stream': stream,
        if (request.format == LlmResponseFormat.json) 'format': 'json',
        'options': <String, dynamic>{
          'temperature': request.temperature,
          'num_predict': request.maxTokens,
        },
      };

  @override
  Future<LlmCompletion> complete(LlmRequest request) async {
    final response = await _http
        .post(
          Uri.parse('$_baseUrl/api/chat'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(_body(request, stream: false)),
        )
        // Local models on a laptop are slower to first token than a hosted API,
        // so the timeout is generous.
        .timeout(request.timeout * 2);

    if (response.statusCode != 200) {
      throw AiFailure(
        describeStatus(response.statusCode, response.body),
        provider: providerId,
        retryable: isRetryable(response.statusCode),
      );
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final message = json['message'] as Map<String, dynamic>?;

    return LlmCompletion(
      text: message?['content'] as String? ?? '',
      model: json['model'] as String? ?? model,
      promptTokens: json['prompt_eval_count'] as int?,
      completionTokens: json['eval_count'] as int?,
      finishReason: json['done_reason'] as String?,
    );
  }

  @override
  Stream<String> stream(LlmRequest request) async* {
    final httpRequest = http.Request('POST', Uri.parse('$_baseUrl/api/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(_body(request, stream: true));

    final response = await _http.send(httpRequest).timeout(request.timeout * 2);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AiFailure(
        describeStatus(response.statusCode, body),
        provider: providerId,
        retryable: isRetryable(response.statusCode),
      );
    }

    // Ollama streams newline-delimited JSON rather than SSE.
    var buffer = '';
    await for (final chunk
        in response.stream.transform(const Utf8Decoder(allowMalformed: true))) {
      buffer += chunk;
      while (true) {
        final newline = buffer.indexOf('\n');
        if (newline < 0) break;
        final line = buffer.substring(0, newline).trim();
        buffer = buffer.substring(newline + 1);
        if (line.isEmpty) continue;

        final json = jsonDecode(line) as Map<String, dynamic>;
        final content =
            (json['message'] as Map<String, dynamic>?)?['content'] as String?;
        if (content != null && content.isNotEmpty) yield content;
      }
    }
  }

  @override
  Future<bool> ping() async {
    try {
      final response = await _http
          .get(Uri.parse('$_baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
