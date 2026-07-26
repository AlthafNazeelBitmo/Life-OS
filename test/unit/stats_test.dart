import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/utils/stats.dart';

void main() {
  group('Stats.pearson', () {
    test('detects a perfect positive relationship', () {
      final r = Stats.pearson(
        <double>[1, 2, 3, 4, 5],
        <double>[2, 4, 6, 8, 10],
      );
      expect(r, closeTo(1, 0.0001));
    });

    test('detects a perfect negative relationship', () {
      final r = Stats.pearson(
        <double>[1, 2, 3, 4, 5],
        <double>[10, 8, 6, 4, 2],
      );
      expect(r, closeTo(-1, 0.0001));
    });

    test('returns zero when one series never varies', () {
      // This is the case that matters in practice: a habit logged every single
      // day explains nothing about mood, and must not produce a correlation.
      final r = Stats.pearson(
        <double>[1, 1, 1, 1, 1],
        <double>[3, 8, 2, 9, 4],
      );
      expect(r, 0);
    });

    test('returns zero for samples too small to mean anything', () {
      expect(Stats.pearson(<double>[1, 2], <double>[2, 4]), 0);
    });
  });

  group('Stats.trend', () {
    test('is positive for a rising series and negative for a falling one', () {
      expect(Stats.trend(<double>[1, 2, 3, 4]), greaterThan(0));
      expect(Stats.trend(<double>[4, 3, 2, 1]), lessThan(0));
      expect(Stats.trend(<double>[3, 3, 3]), 0);
    });
  });

  group('Stats.effectSize', () {
    test('is near zero when both groups look the same', () {
      final d = Stats.effectSize(
        <double>[5, 6, 5, 6, 5],
        <double>[5, 6, 5, 6, 5],
      );
      expect(d.abs(), lessThan(0.01));
    });

    test('is large when the groups separate cleanly', () {
      final d = Stats.effectSize(
        <double>[8, 9, 8, 9, 8],
        <double>[3, 4, 3, 4, 3],
      );
      expect(d, greaterThan(2));
    });

    test('returns zero for undersized groups', () {
      expect(Stats.effectSize(<double>[1, 2], <double>[3, 4]), 0);
    });
  });

  test('mean and stdDev handle empty and single-value input safely', () {
    expect(Stats.mean(<double>[]), 0);
    expect(Stats.stdDev(<double>[]), 0);
    expect(Stats.stdDev(<double>[5]), 0);
    expect(Stats.mean(<double>[2, 4, 6]), 4);
  });

  test('percentile reports the share of the population below a value', () {
    final population = <double>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    expect(Stats.percentile(5.5, population), 0.5);
    expect(Stats.percentile(0, population), 0);
  });
}
