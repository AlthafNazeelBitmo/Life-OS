import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/failures.dart';
import '../llm_client.dart';
import '../models/llm.dart';
import 'sse.dart';

class GeminiClient with LlmHttpErrors implements LlmClient {
  GeminiClient({
    required String apiKey,
    required this.model,
    http.Client? httpClient,
    String baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
  })  : _apiKey = apiKey,
        _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl;

  final String _apiKey;
  final http.Client _http;
  final String _baseUrl;

  @override
  final String model;

  @override
  String get providerId => 'gemini';

  Map<String, dynamic> _body(LlmRequest request) {
    final system = request.systemPrompt;
    return <String, dynamic>{
      'contents': <Map<String, dynamic>>[
        for (final message in request.conversation)
          <String, dynamic>{
            // Gemini calls the assistant turn "model".
            'role': message.role == LlmRole.assistant ? 'model' : 'user',
            'parts': <Map<String, String>>[
              <String, String>{'text': message.content},
            ],
          },
      ],
      if (system.isNotEmpty)
        'systemInstruction': <String, dynamic>{
          'parts': <Map<String, String>>[<String, String>{'text': system}],
        },
      'generationConfig': <String, dynamic>{
        'temperature': request.temperature,
        'maxOutputTokens': request.maxTokens,
        if (request.format == LlmResponseFormat.json)
          'responseMimeType': 'application/json',
      },
    };
  }

  String _extractText(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return '';
    final content =
        (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>? ?? const <dynamic>[];
    return parts
        .whereType<Map<String, dynamic>>()
        .map((part) => part['text'] as String? ?? '')
        .join();
  }

  @override
  Future<LlmCompletion> complete(LlmRequest request) async {
    final target = request.model ?? model;
    final response = await _http
        .post(
          Uri.parse('$_baseUrl/models/$target:generateContent?key=$_apiKey'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(_body(request)),
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
    final usage = json['usageMetadata'] as Map<String, dynamic>?;
    final candidates = json['candidates'] as List<dynamic>?;

    return LlmCompletion(
      text: _extractText(json),
      model: target,
      promptTokens: usage?['promptTokenCount'] as int?,
      completionTokens: usage?['candidatesTokenCount'] as int?,
      finishReason: candidates == null || candidates.isEmpty
          ? null
          : (candidates.first as Map<String, dynamic>)['finishReason'] as String?,
    );
  }

  @override
  Stream<String> stream(LlmRequest request) async* {
    final target = request.model ?? model;
    final httpRequest = http.Request(
      'POST',
      Uri.parse(
        '$_baseUrl/models/$target:streamGenerateContent?alt=sse&key=$_apiKey',
      ),
    )
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(_body(request));

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
      final text = _extractText(jsonDecode(payload) as Map<String, dynamic>);
      if (text.isNotEmpty) yield text;
    }
  }

  @override
  Future<bool> ping() async {
    try {
      final response = await _http
          .get(Uri.parse('$_baseUrl/models?key=$_apiKey'))
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
