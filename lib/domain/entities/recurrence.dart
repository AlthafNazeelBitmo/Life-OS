import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/extensions/date_time_x.dart';

part 'recurrence.freezed.dart';
part 'recurrence.g.dart';

enum RecurrenceUnit { day, week, month, year }

/// Repetition rule shared by tasks, calendar events, bills and habits.
///
/// A deliberately small subset of RFC 5545: enough for "every weekday",
/// "every 2 weeks on Mon/Thu", "the 1st of each month", without dragging in a
/// full iCalendar engine. [weekdays] uses `DateTime.monday`..`DateTime.sunday`.
@freezed
abstract class Recurrence with _$Recurrence {
  const factory Recurrence({
    required RecurrenceUnit unit,
    @Default(1) int interval,
    @Default(<int>[]) List<int> weekdays,
    int? dayOfMonth,
    DateTime? until,
    int? count,
  }) = _Recurrence;

  const Recurrence._();

  factory Recurrence.daily() => const Recurrence(unit: RecurrenceUnit.day);

  factory Recurrence.weekdays() => const Recurrence(
        unit: RecurrenceUnit.week,
        weekdays: <int>[
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
        ],
      );

  factory Recurrence.monthlyOn(int day) =>
      Recurrence(unit: RecurrenceUnit.month, dayOfMonth: day);

  factory Recurrence.fromJson(Map<String, dynamic> json) =>
      _$RecurrenceFromJson(json);

  /// Whether [date] is an occurrence, counting from [anchor].
  bool occursOn(DateTime date, {required DateTime anchor}) {
    final day = date.startOfDay;
    final start = anchor.startOfDay;
    if (day.isBefore(start)) return false;
    if (until != null && day.isAfter(until!.startOfDay)) return false;

    switch (unit) {
      case RecurrenceUnit.day:
        return start.daysBetween(day) % interval == 0;
      case RecurrenceUnit.week:
        final weeksApart = start.startOfWeek.daysBetween(day.startOfWeek) ~/ 7;
        if (weeksApart % interval != 0) return false;
        return weekdays.isEmpty
            ? day.weekday == start.weekday
            : weekdays.contains(day.weekday);
      case RecurrenceUnit.month:
        final monthsApart =
            (day.year - start.year) * 12 + (day.month - start.month);
        if (monthsApart % interval != 0) return false;
        final target = dayOfMonth ?? start.day;
        // Clamp so "the 31st" still fires in short months.
        final lastDay = DateTime(day.year, day.month + 1, 0).day;
        return day.day == (target > lastDay ? lastDay : target);
      case RecurrenceUnit.year:
        if ((day.year - start.year) % interval != 0) return false;
        return day.month == start.month && day.day == start.day;
    }
  }

  /// Next occurrence strictly after [from].
  DateTime? nextAfter(DateTime from, {required DateTime anchor}) {
    var cursor = from.startOfDay.add(const Duration(days: 1));
    // 800 days covers every supported rule, including yearly with interval 2.
    for (var i = 0; i < 800; i++) {
      if (occursOn(cursor, anchor: anchor)) return cursor;
      if (until != null && cursor.isAfter(until!)) return null;
      cursor = cursor.add(const Duration(days: 1));
    }
    return null;
  }

  String get label => switch (unit) {
        RecurrenceUnit.day =>
          interval == 1 ? 'Every day' : 'Every $interval days',
        RecurrenceUnit.week when weekdays.isNotEmpty =>
          'Every ${weekdays.map(_weekdayName).join(', ')}',
        RecurrenceUnit.week =>
          interval == 1 ? 'Every week' : 'Every $interval weeks',
        RecurrenceUnit.month =>
          interval == 1 ? 'Every month' : 'Every $interval months',
        RecurrenceUnit.year => 'Every year',
      };

  static String _weekdayName(int weekday) => const <String>[
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][(weekday - 1) % 7];
}
