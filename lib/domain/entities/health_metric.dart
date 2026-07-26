import 'package:freezed_annotation/freezed_annotation.dart';

part 'health_metric.freezed.dart';
part 'health_metric.g.dart';

/// Everything the health module tracks, with its canonical unit and a sensible
/// daily target. One table serves every metric, so adding a new one is a single
/// enum value rather than a migration.
enum HealthKind {
  weight('Weight', 'kg', 0, false),
  water('Water', 'glasses', 8, true),
  sleep('Sleep', 'h', 8, true),
  exercise('Exercise', 'min', 30, true),
  steps('Steps', 'steps', 8000, true),
  calories('Calories', 'kcal', 2000, false),
  heartRate('Resting HR', 'bpm', 0, false),
  screenTime('Screen time', 'h', 3, false);

  const HealthKind(this.label, this.unit, this.defaultTarget, this.cumulative);

  final String label;
  final String unit;

  /// 0 means "no meaningful default target" (e.g. weight).
  final double defaultTarget;

  /// True when several readings in a day should be summed rather than averaged.
  final bool cumulative;
}

@freezed
abstract class HealthMetric with _$HealthMetric {
  const factory HealthMetric({
    required String id,
    required HealthKind kind,
    required double value,
    required DateTime recordedAt,
    required String dayKey,
    @Default('') String note,

    /// `manual`, `healthkit`, `googlefit`, `voice`.
    @Default('manual') String source,
  }) = _HealthMetric;

  factory HealthMetric.fromJson(Map<String, dynamic> json) =>
      _$HealthMetricFromJson(json);
}

/// One day's roll-up per metric, which is what charts and the dashboard read.
@freezed
abstract class DailyHealthSummary with _$DailyHealthSummary {
  const factory DailyHealthSummary({
    required String dayKey,
    @Default(<HealthKind, double>{}) Map<HealthKind, double> values,
  }) = _DailyHealthSummary;

  const DailyHealthSummary._();

  factory DailyHealthSummary.fromJson(Map<String, dynamic> json) =>
      _$DailyHealthSummaryFromJson(json);

  double? valueOf(HealthKind kind) => values[kind];

  double progressOf(HealthKind kind, {double? target}) {
    final goal = target ?? kind.defaultTarget;
    if (goal <= 0) return 0;
    return ((values[kind] ?? 0) / goal).clamp(0.0, 1.0);
  }
}
