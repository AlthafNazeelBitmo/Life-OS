import 'package:flutter/foundation.dart';

import '../../domain/entities/chat.dart';

/// Return types for [AIService].
///
/// Hand-written rather than code-generated on purpose: these parse *model
/// output*, which is only mostly well-formed. Every constructor here tolerates
/// missing keys, wrong-typed numbers and absent lists, because the alternative
/// is a thrown exception the user experiences as "the AI is broken".

int _asInt(Object? value, [int fallback = 0]) => switch (value) {
      final int v => v,
      final double v => v.round(),
      final String v => int.tryParse(v) ?? fallback,
      _ => fallback,
    };

double _asDouble(Object? value, [double fallback = 0]) => switch (value) {
      final double v => v,
      final int v => v.toDouble(),
      final String v => double.tryParse(v) ?? fallback,
      _ => fallback,
    };

List<String> _asStrings(Object? value) => switch (value) {
      final List<dynamic> list =>
        list.map((item) => item.toString()).where((s) => s.isNotEmpty).toList(),
      final String single when single.isNotEmpty => <String>[single],
      _ => const <String>[],
    };

@immutable
class AiSummary {
  const AiSummary({
    required this.summary,
    this.keyPoints = const <String>[],
    this.topics = const <String>[],
    this.citations = const <Citation>[],
    this.model,
  });

  factory AiSummary.fromJson(Map<String, dynamic> json) => AiSummary(
        summary: json['summary'] as String? ?? '',
        keyPoints: _asStrings(json['key_points'] ?? json['keyPoints']),
        topics: _asStrings(json['topics'] ?? json['themes']),
      );

  final String summary;
  final List<String> keyPoints;
  final List<String> topics;
  final List<Citation> citations;
  final String? model;

  AiSummary withCitations(List<Citation> citations, String? model) => AiSummary(
        summary: summary,
        keyPoints: keyPoints,
        topics: topics,
        citations: citations,
        model: model,
      );
}

@immutable
class MoodAnalysis {
  const MoodAnalysis({
    this.emotions = const <String>[],
    this.sentiment = 0,
    this.themes = const <String>[],
    this.events = const <String>[],
    this.people = const <String>[],
    this.note = '',
  });

  factory MoodAnalysis.fromJson(Map<String, dynamic> json) => MoodAnalysis(
        emotions: _asStrings(json['emotions']),
        sentiment: _asDouble(json['sentiment']).clamp(-1.0, 1.0),
        themes: _asStrings(json['themes']),
        events: _asStrings(json['events']),
        people: _asStrings(json['people']),
        note: json['note'] as String? ?? '',
      );

  /// Named feelings, in the user's own register where possible.
  final List<String> emotions;

  /// -1 … 1.
  final double sentiment;
  final List<String> themes;

  /// Things that actually happened, for the timeline.
  final List<String> events;
  final List<String> people;
  final String note;

  String get label => switch (sentiment) {
        >= 0.5 => 'Positive',
        >= 0.15 => 'Leaning positive',
        > -0.15 => 'Neutral',
        > -0.5 => 'Leaning negative',
        _ => 'Negative',
      };
}

@immutable
class AiAnswer {
  const AiAnswer({
    required this.text,
    this.citations = const <Citation>[],
    this.confidence = 1,
    this.usedFallback = false,
    this.model,
  });

  final String text;
  final List<Citation> citations;

  /// Drops when the model cited tokens that did not resolve to real records.
  final double confidence;

  /// True when the answer came from the on-device provider rather than a model.
  final bool usedFallback;
  final String? model;

  bool get isGrounded => citations.isNotEmpty;
}

/// What the assistant heard in a spoken command, normalised into something the
/// app can act on without another round trip.
@immutable
class ParsedIntent {
  const ParsedIntent({
    required this.action,
    this.fields = const <String, Object?>{},
    this.confidence = 0,
    this.transcript = '',
  });

  factory ParsedIntent.fromJson(Map<String, dynamic> json) => ParsedIntent(
        action: json['action'] as String? ?? 'unknown',
        fields: (json['fields'] as Map<String, dynamic>?) ??
            const <String, Object?>{},
        confidence: _asDouble(json['confidence'], 0.5).clamp(0.0, 1.0),
      );

  /// `log_expense`, `log_habit`, `add_task`, `add_event`, `log_mood`,
  /// `log_health`, `create_goal`, `journal`, or `unknown`.
  final String action;
  final Map<String, Object?> fields;
  final double confidence;
  final String transcript;

  String? get stringField => fields['text'] as String?;

  int? get amountMinor {
    final raw = fields['amount_minor'] ?? fields['amountMinor'];
    if (raw == null) {
      final major = fields['amount'];
      return major == null ? null : (_asDouble(major) * 100).round();
    }
    return _asInt(raw);
  }

  DateTime? get when {
    final raw = fields['when'] ?? fields['date'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  ParsedIntent withTranscript(String value) => ParsedIntent(
        action: action,
        fields: fields,
        confidence: confidence,
        transcript: value,
      );
}
