import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/domain/entities/recurrence.dart';

void main() {
  // A Monday, so weekday arithmetic in the tests reads clearly.
  final anchor = DateTime(2026, 7, 6);

  group('Recurrence.occursOn', () {
    test('daily fires every day from the anchor', () {
      final rule = Recurrence.daily();

      expect(rule.occursOn(anchor, anchor: anchor), isTrue);
      expect(rule.occursOn(anchor.add(const Duration(days: 1)), anchor: anchor),
          isTrue);
      expect(
        rule.occursOn(anchor.subtract(const Duration(days: 1)), anchor: anchor),
        isFalse,
        reason: 'nothing occurs before the anchor',
      );
    });

    test('every-N-days respects the interval', () {
      const rule = Recurrence(unit: RecurrenceUnit.day, interval: 3);

      expect(rule.occursOn(anchor, anchor: anchor), isTrue);
      expect(rule.occursOn(anchor.add(const Duration(days: 3)), anchor: anchor),
          isTrue);
      expect(rule.occursOn(anchor.add(const Duration(days: 2)), anchor: anchor),
          isFalse);
    });

    test('weekdays rule skips the weekend', () {
      final rule = Recurrence.weekdays();

      expect(rule.occursOn(DateTime(2026, 7, 10), anchor: anchor), isTrue,
          reason: 'Friday');
      expect(rule.occursOn(DateTime(2026, 7, 11), anchor: anchor), isFalse,
          reason: 'Saturday');
      expect(rule.occursOn(DateTime(2026, 7, 12), anchor: anchor), isFalse,
          reason: 'Sunday');
      expect(rule.occursOn(DateTime(2026, 7, 13), anchor: anchor), isTrue,
          reason: 'Monday');
    });

    test('fortnightly only fires on matching weeks', () {
      const rule = Recurrence(
        unit: RecurrenceUnit.week,
        interval: 2,
        weekdays: <int>[DateTime.monday],
      );

      expect(rule.occursOn(DateTime(2026, 7, 6), anchor: anchor), isTrue);
      expect(rule.occursOn(DateTime(2026, 7, 13), anchor: anchor), isFalse);
      expect(rule.occursOn(DateTime(2026, 7, 20), anchor: anchor), isTrue);
    });

    test('monthly clamps to the last day in short months', () {
      final rule = Recurrence.monthlyOn(31);
      final start = DateTime(2026, 1, 31);

      expect(rule.occursOn(DateTime(2026, 1, 31), anchor: start), isTrue);
      // February has 28 days in 2026, so the 28th is the occurrence.
      expect(rule.occursOn(DateTime(2026, 2, 28), anchor: start), isTrue);
      expect(rule.occursOn(DateTime(2026, 2, 27), anchor: start), isFalse);
    });

    test('yearly matches the same month and day', () {
      const rule = Recurrence(unit: RecurrenceUnit.year);

      expect(rule.occursOn(DateTime(2027, 7, 6), anchor: anchor), isTrue);
      expect(rule.occursOn(DateTime(2027, 7, 7), anchor: anchor), isFalse);
    });

    test('respects the until date', () {
      final rule = Recurrence(
        unit: RecurrenceUnit.day,
        until: anchor.add(const Duration(days: 2)),
      );

      expect(rule.occursOn(anchor.add(const Duration(days: 2)), anchor: anchor),
          isTrue);
      expect(rule.occursOn(anchor.add(const Duration(days: 3)), anchor: anchor),
          isFalse);
    });
  });

  group('Recurrence.nextAfter', () {
    test('finds the next weekday occurrence across a weekend', () {
      final rule = Recurrence.weekdays();
      final friday = DateTime(2026, 7, 10);

      expect(
        rule.nextAfter(friday, anchor: anchor),
        DateTime(2026, 7, 13),
      );
    });

    test('returns null once the rule has expired', () {
      final rule = Recurrence(
        unit: RecurrenceUnit.day,
        until: anchor.add(const Duration(days: 1)),
      );

      expect(
        rule.nextAfter(anchor.add(const Duration(days: 1)), anchor: anchor),
        isNull,
      );
    });
  });

  test('label describes the rule in plain language', () {
    expect(Recurrence.daily().label, 'Every day');
    expect(
      const Recurrence(unit: RecurrenceUnit.day, interval: 3).label,
      'Every 3 days',
    );
    expect(Recurrence.weekdays().label, 'Every Mon, Tue, Wed, Thu, Fri');
  });
}
