import 'package:freezed_annotation/freezed_annotation.dart';

import 'chat.dart';

part 'insight.freezed.dart';
part 'insight.g.dart';

enum InsightKind {
  pattern,
  correlation,
  achievement,
  warning,
  recommendation,
  milestone,
}

enum ReviewPeriod {
  weekly('Weekly review'),
  monthly('Monthly review'),
  quarterly('Quarterly review'),
  yearly('Yearly review');

  const ReviewPeriod(this.label);

  final String label;
}

/// One observation about the user's life.
///
/// Every insight carries its [citations] and a [confidence]; the UI shows the
/// sources inline, and low-confidence items are phrased as questions rather
/// than statements.
@freezed
abstract class Insight with _$Insight {
  const factory Insight({
    required String id,
    required InsightKind kind,
    required String title,
    required String body,
    required DateTime createdAt,
    @Default(<Citation>[]) List<Citation> citations,

    /// 0–1. Below 0.5 the card is rendered as "possible pattern".
    @Default(0.7) double confidence,
    DateTime? periodStart,
    DateTime? periodEnd,

    /// Machine-readable payload for chartable insights, e.g.
    /// `{"x": "exercise", "y": "happiness", "r": 0.62}`.
    @Default(<String, dynamic>{}) Map<String, dynamic> data,
    @Default(false) bool pinned,
    @Default(false) bool dismissed,
    String? model,
  }) = _Insight;

  const Insight._();

  factory Insight.fromJson(Map<String, dynamic> json) =>
      _$InsightFromJson(json);

  bool get isTentative => confidence < 0.5;
}

/// A period review: the narrative plus the numbers behind it.
@freezed
abstract class PeriodReview with _$PeriodReview {
  const factory PeriodReview({
    required String id,
    required ReviewPeriod period,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime generatedAt,
    @Default('') String headline,
    @Default('') String narrative,
    @Default(<String>[]) List<String> wins,
    @Default(<String>[]) List<String> attentionAreas,
    @Default(<String>[]) List<String> recommendations,
    @Default(<Insight>[]) List<Insight> insights,
    @Default(<String, double>{}) Map<String, double> metrics,
    @Default(<Citation>[]) List<Citation> citations,
    String? model,
  }) = _PeriodReview;

  factory PeriodReview.fromJson(Map<String, dynamic> json) =>
      _$PeriodReviewFromJson(json);
}

/// Combined 0–100 wellbeing figure shown on the dashboard.
///
/// Each pillar is scored independently so the UI can say *why* the number moved
/// instead of showing an unexplained score.
@freezed
abstract class LifeScore with _$LifeScore {
  const factory LifeScore({
    required DateTime computedAt,
    @Default(0) int habits,
    @Default(0) int health,
    @Default(0) int finances,
    @Default(0) int productivity,
    @Default(0) int mood,

    /// Pillars with too little data to score, excluded from the average.
    @Default(<String>[]) List<String> missingPillars,
  }) = _LifeScore;

  const LifeScore._();

  factory LifeScore.fromJson(Map<String, dynamic> json) =>
      _$LifeScoreFromJson(json);

  Map<String, int> get pillars => <String, int>{
        'Habits': habits,
        'Health': health,
        'Finances': finances,
        'Productivity': productivity,
        'Mood': mood,
      };

  int get total {
    final scored = pillars.entries
        .where((entry) => !missingPillars.contains(entry.key))
        .map((entry) => entry.value)
        .toList();
    if (scored.isEmpty) return 0;
    return (scored.reduce((a, b) => a + b) / scored.length).round();
  }

  String get band => switch (total) {
        >= 85 => 'Thriving',
        >= 70 => 'Steady',
        >= 50 => 'Mixed',
        >= 30 => 'Strained',
        _ => 'Running on empty',
      };
}
