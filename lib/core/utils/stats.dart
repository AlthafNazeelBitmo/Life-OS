import 'dart:math' as math;

/// Small statistics helpers used by the on-device analytics.
///
/// These exist so that the common insights ("you sleep better after exercise")
/// can be computed locally, offline, and for free — the language model is only
/// asked to *narrate* patterns that were found here, never to invent them.
abstract final class Stats {
  const Stats._();

  static double mean(Iterable<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double stdDev(Iterable<double> values) {
    if (values.length < 2) return 0;
    final m = mean(values);
    final variance =
        values.map((v) => math.pow(v - m, 2).toDouble()).reduce((a, b) => a + b) /
            (values.length - 1);
    return math.sqrt(variance);
  }

  /// Pearson correlation. Returns 0 when either series is constant, since a
  /// flat series carries no information about the other.
  static double pearson(List<double> xs, List<double> ys) {
    final n = math.min(xs.length, ys.length);
    if (n < 3) return 0;
    final mx = mean(xs.take(n));
    final my = mean(ys.take(n));
    var numerator = 0.0;
    var sumSqX = 0.0;
    var sumSqY = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = xs[i] - mx;
      final dy = ys[i] - my;
      numerator += dx * dy;
      sumSqX += dx * dx;
      sumSqY += dy * dy;
    }
    final denominator = math.sqrt(sumSqX * sumSqY);
    if (denominator == 0) return 0;
    return (numerator / denominator).clamp(-1.0, 1.0);
  }

  /// Slope of the least-squares line through [values], in units per step.
  /// Positive means the metric is trending up over the window.
  static double trend(List<double> values) {
    if (values.length < 2) return 0;
    final xs = List<double>.generate(values.length, (i) => i.toDouble());
    final mx = mean(xs);
    final my = mean(values);
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < values.length; i++) {
      numerator += (xs[i] - mx) * (values[i] - my);
      denominator += math.pow(xs[i] - mx, 2).toDouble();
    }
    return denominator == 0 ? 0 : numerator / denominator;
  }

  /// Difference in means between the days a factor was present and the days it
  /// was not, expressed in standard deviations (Cohen's d). More honest than a
  /// raw average gap when the metric is noisy.
  static double effectSize(List<double> withFactor, List<double> without) {
    if (withFactor.length < 3 || without.length < 3) return 0;
    final pooled = math.sqrt(
      (math.pow(stdDev(withFactor), 2) + math.pow(stdDev(without), 2)) / 2,
    );
    if (pooled == 0) return 0;
    return (mean(withFactor) - mean(without)) / pooled;
  }

  /// Percentile of [value] within [population], 0–1.
  static double percentile(double value, List<double> population) {
    if (population.isEmpty) return 0;
    final below = population.where((v) => v < value).length;
    return below / population.length;
  }
}
