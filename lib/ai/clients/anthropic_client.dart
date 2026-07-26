import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/failures.dart';
import '../llm_client.dart';
import '../models/llm.dart';
import 'sse.dart';

class AnthropicClient with LlmHttpErrors implements LlmClient {
  AnthropicClient({
    required String apiKey,
    required this.model,
    http.Client? httpClient,
    String baseUrl = 'https://api.anthropic.com/v1',
  })  : _apiKey = apiKey,
        _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl;

  final String _apiKey;
  final http.Client _http;
  final String _baseUrl;

  @override
  final String model;

  @override
  String get providerId => 'anthropic';

  Map<String, String> get _headers => <String, String>{
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> _body(LlmRequest request, {required bool stream}) {
    final system = request.systemPrompt;
    return <String, dynamic>{
      'model': request.model ?? model,
      'max_tokens': request.maxTokens,
      'temperature': request.temperature,
      'stream': stream,
      // Anthropic takes the system prompt as a top-level field rather than a
      // message, which is why LlmRequest keeps the two separable.
      if (system.isNotEmpty) 'system': system,
      'messages': request.conversation.map((m) => m.toJson()).toList(),
    };
  }

  @override
  Future<LlmCompletion> complete(LlmRequest request) async {
    final response = await _http
        .post(
          Uri.parse('$_baseUrl/messages'),
          headers: _headers,
          body: jsonEncode(_body(request, stream: false)),
        )
        .timeout(request.timeout);

    if (response.statusCode != 200) {
      throw AiFailure(
        describeStatus(response.statusCode, response.body),
        provider: providerId,
        retryable: isRetryable(response.statusCode),
      );
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final blocks = json['content'] as List<dynamic>? ?? const <dynamic>[];
    final text = blocks
        .whereType<Map<String, dynamic>>()
        .where((block) => block['type'] == 'text')
        .map((block) => block['text'] as String? ?? '')
        .join();
    final usage = json['usage'] as Map<String, dynamic>?;

    return LlmCompletion(
      text: text,
      model: json['model'] as String? ?? model,
      promptTokens: usage?['input_tokens'] as int?,
      completionTokens: usage?['output_tokens'] as int?,
      finishReason: json['stop_reason'] as String?,
    );
  }

  @override
  Stream<String> stream(LlmRequest request) async* {
    final httpRequest = http.Request('POST', Uri.parse('$_baseUrl/messages'))
      ..headers.addAll(_headers)
      ..body = jsonEncode(_body(request, stream: true));

    final response = await _http.send(httpRequest).timeout(request.timeout);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AiFailure(
        describeStatus(response.statusCode, body),
        provider: providerId,
        retryable: isRetryable(response.statusCode),
      );
    }

    await for (final payload in sseEvents(response)) {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      if (json['type'] != 'content_block_delta') continue;
      final delta = json['delta'] as Map<String, dynamic>?;
      final text = delta?['text'] as String?;
      if (text != null && text.isNotEmpty) yield text;
    }
  }

  @override
  Future<bool> ping() async {
    try {
      // No cheap list endpoint here, so the probe is a one-token completion.
      final response = await _http
          .post(
            Uri.parse('$_baseUrl/messages'),
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              'model': model,
              'max_tokens': 1,
              'messages': <Map<String, String>>[
                <String, String>{'role': 'user', 'content': 'ping'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
