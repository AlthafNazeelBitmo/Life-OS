import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/failures.dart';
import '../llm_client.dart';
import '../models/llm.dart';
import 'sse.dart';

class OpenAiClient with LlmHttpErrors implements LlmClient {
  OpenAiClient({
    required String apiKey,
    required this.model,
    http.Client? httpClient,
    String baseUrl = 'https://api.openai.com/v1',
  })  : _apiKey = apiKey,
        _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl;

  final String _apiKey;
  final http.Client _http;
  final String _baseUrl;

  @override
  final String model;

  @override
  String get providerId => 'openai';

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> _body(LlmRequest request, {required bool stream}) =>
      <String, dynamic>{
        'model': request.model ?? model,
        'messages': request.messages.map((m) => m.toJson()).toList(),
        'temperature': request.temperature,
        'max_tokens': request.maxTokens,
        'stream': stream,
        if (request.format == LlmResponseFormat.json)
          'response_format': <String, String>{'type': 'json_object'},
      };

  @override
  Future<LlmCompletion> complete(LlmRequest request) async {
    final response = await _http
        .post(
          Uri.parse('$_baseUrl/chat/completions'),
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

    final json = jsonDecode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;
    final choice = (json['choices'] as List<dynamic>).first
        as Map<String, dynamic>;
    final usage = json['usage'] as Map<String, dynamic>?;

    return LlmCompletion(
      text: (choice['message'] as Map<String, dynamic>)['content'] as String? ??
          '',
      model: json['model'] as String? ?? model,
      promptTokens: usage?['prompt_tokens'] as int?,
      completionTokens: usage?['completion_tokens'] as int?,
      finishReason: choice['finish_reason'] as String?,
    );
  }

  @override
  Stream<String> stream(LlmRequest request) async* {
    final httpRequest = http.Request(
      'POST',
      Uri.parse('$_baseUrl/chat/completions'),
    )
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
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) continue;
      final delta =
          (choices.first as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
      final content = delta?['content'] as String?;
      if (content != null && content.isNotEmpty) yield content;
    }
  }

  @override
  Future<bool> ping() async {
    try {
      final response = await _http
          .get(Uri.parse('$_baseUrl/models'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
