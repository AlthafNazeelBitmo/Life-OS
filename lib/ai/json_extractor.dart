import 'dart:convert';

/// Pulls a JSON object out of model output.
///
/// Even with `response_format: json_object` set, models occasionally wrap their
/// answer in prose or a ```json fence. Treating that as a hard failure would
/// surface to the user as "the AI is broken", so parsing degrades in stages:
/// strict decode → fenced block → first balanced object → give up.
abstract final class JsonExtractor {
  const JsonExtractor._();

  static Map<String, dynamic>? object(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final direct = _tryDecode(text);
    if (direct != null) return direct;

    final fenced = _fencedBlock(text);
    if (fenced != null) {
      final decoded = _tryDecode(fenced);
      if (decoded != null) return decoded;
    }

    final balanced = _firstBalancedObject(text);
    if (balanced != null) return _tryDecode(balanced);

    return null;
  }

  /// Same, for a response whose top level is an array.
  static List<dynamic>? array(String raw) {
    final decoded = _tryDecodeAny(raw.trim());
    if (decoded is List) return decoded;

    final fenced = _fencedBlock(raw);
    if (fenced != null) {
      final inner = _tryDecodeAny(fenced);
      if (inner is List) return inner;
    }
    return null;
  }

  static Map<String, dynamic>? _tryDecode(String text) {
    final decoded = _tryDecodeAny(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static Object? _tryDecodeAny(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static String? _fencedBlock(String text) {
    final match = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(1)?.trim();
  }

  /// Scans for the first `{` and returns through its matching `}`, ignoring
  /// braces that appear inside string literals.
  static String? _firstBalancedObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      // A single backslash. Not a raw string: Dart forbids a raw string ending
      // in a backslash, and r'\\' would be two characters, not one.
      if (char == '\\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  /// Every `[token]` reference in a piece of model prose.
  static List<String> citationTokens(String text) => RegExp(r'\[([a-z]{1,2}\d{1,3})\]')
      .allMatches(text)
      .map((match) => match.group(1)!)
      .toList();
}
