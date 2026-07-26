import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/ai/json_extractor.dart';

void main() {
  group('JsonExtractor.object', () {
    test('parses a clean JSON object', () {
      final json = JsonExtractor.object('{"summary": "hi", "n": 2}');

      expect(json, isNotNull);
      expect(json!['summary'], 'hi');
      expect(json['n'], 2);
    });

    test('recovers JSON from a fenced code block', () {
      const raw = '''
Here you go:

```json
{"summary": "fenced"}
```
''';
      expect(JsonExtractor.object(raw)?['summary'], 'fenced');
    });

    test('recovers JSON wrapped in prose', () {
      // Models do this even when asked for JSON only; treating it as a hard
      // failure would show the user "the AI is broken" for a parseable answer.
      const raw = 'Sure! {"summary": "inline"} Hope that helps.';
      expect(JsonExtractor.object(raw)?['summary'], 'inline');
    });

    test('handles braces inside string values', () {
      const raw = 'text {"summary": "a } brace", "ok": true} tail';
      final json = JsonExtractor.object(raw);

      expect(json?['summary'], 'a } brace');
      expect(json?['ok'], true);
    });

    test('handles nested objects', () {
      const raw = '{"a": {"b": {"c": 1}}, "d": 2}';
      final json = JsonExtractor.object(raw);

      expect((json!['a'] as Map<String, dynamic>)['b'], isA<Map<String, dynamic>>());
      expect(json['d'], 2);
    });

    test('returns null when there is nothing to parse', () {
      expect(JsonExtractor.object('no json at all'), isNull);
      expect(JsonExtractor.object(''), isNull);
      expect(JsonExtractor.object('{"unterminated": '), isNull);
    });
  });

  group('JsonExtractor.array', () {
    test('parses top-level and fenced arrays', () {
      expect(JsonExtractor.array('[1, 2, 3]'), <int>[1, 2, 3]);
      expect(JsonExtractor.array('```json\n["a"]\n```'), <String>['a']);
    });
  });

  group('JsonExtractor.citationTokens', () {
    test('extracts every bracket token in order', () {
      const text = 'You slept well [h1] and journalled [j12] that evening.';
      expect(JsonExtractor.citationTokens(text), <String>['h1', 'j12']);
    });

    test('ignores bracketed text that is not a token', () {
      const text = 'A note [see here] and a real one [m3].';
      expect(JsonExtractor.citationTokens(text), <String>['m3']);
    });

    test('returns empty when the model cited nothing', () {
      expect(JsonExtractor.citationTokens('No sources at all.'), isEmpty);
    });
  });
}
