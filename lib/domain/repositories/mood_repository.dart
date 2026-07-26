import '../../core/error/result.dart';
import '../entities/mood_entry.dart';

/// A correlation the pattern engine found between something the user did and
/// how they felt afterwards.
class MoodCorrelation {
  const MoodCorrelation({
    required this.factor,
    required this.dimension,
    required this.coefficient,
    required this.sampleSize,
    required this.description,
  });

  /// What varied — `exercise`, `sleep>7h`, `journaled`, `habit:meditate`.
  final String factor;
  final MoodDimension dimension;

  /// Pearson r, -1…1.
  final double coefficient;
  final int sampleSize;
  final String description;

  /// Correlations from a handful of days are noise; the UI hides these.
  bool get isMeaningful => sampleSize >= 8 && coefficient.abs() >= 0.35;
}

abstract interface class MoodRepository {
  Stream<List<MoodEntry>> watchRange(DateTime from, DateTime to);

  Stream<MoodEntry?> watchLatest();

  Future<Result<List<MoodEntry>>> range(DateTime from, DateTime to);

  Future<Result<MoodEntry>> upsert(MoodEntry entry);

  Future<Result<void>> delete(String id);

  /// Daily averages of [dimension], ready to plot.
  Future<Result<Map<String, double>>> dailyAverages(
    MoodDimension dimension, {
    required DateTime from,
    required DateTime to,
  });

  /// Runs the on-device correlation pass across habits, health and journalling.
  /// Cheap enough to run on every insights refresh; no model call involved.
  Future<Result<List<MoodCorrelation>>> correlations({int lookbackDays = 90});
}
