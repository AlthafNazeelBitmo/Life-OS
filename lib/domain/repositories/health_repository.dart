import '../../core/error/result.dart';
import '../entities/health_metric.dart';

abstract interface class HealthRepository {
  Stream<DailyHealthSummary> watchDay(DateTime day);

  Stream<List<HealthMetric>> watchKind(
    HealthKind kind, {
    required DateTime from,
    required DateTime to,
  });

  Future<Result<HealthMetric>> record(HealthMetric metric);

  /// Convenience for the dashboard's "+1 glass" style quick actions.
  Future<Result<void>> increment(HealthKind kind, double delta, {DateTime? on});

  Future<Result<void>> delete(String id);

  Future<Result<DailyHealthSummary>> summaryFor(DateTime day);

  /// Daily values for charting, keyed by `yyyy-MM-dd`.
  Future<Result<Map<String, double>>> series(
    HealthKind kind, {
    required DateTime from,
    required DateTime to,
  });

  Future<Result<double?>> average(
    HealthKind kind, {
    required DateTime from,
    required DateTime to,
  });

  /// Per-metric daily targets the user set, falling back to the enum defaults.
  Future<Result<Map<HealthKind, double>>> targets();

  Future<Result<void>> setTarget(HealthKind kind, double target);
}
