/// Calendar arithmetic used across scheduling, streaks and analytics.
///
/// Everything here works on local wall-clock time: a "day" is what the user
/// would call a day, which is what habit streaks and journal entries key on.
extension DateTimeX on DateTime {
  DateTime get startOfDay => DateTime(year, month, day);
  DateTime get endOfDay => DateTime(year, month, day, 23, 59, 59, 999);

  /// Monday-based week start.
  DateTime get startOfWeek =>
      startOfDay.subtract(Duration(days: weekday - DateTime.monday));
  DateTime get endOfWeek => startOfWeek.add(const Duration(days: 7)).previousTick;

  DateTime get startOfMonth => DateTime(year, month);
  DateTime get endOfMonth => DateTime(year, month + 1).previousTick;

  DateTime get startOfQuarter => DateTime(year, ((month - 1) ~/ 3) * 3 + 1);
  DateTime get endOfQuarter =>
      DateTime(year, ((month - 1) ~/ 3) * 3 + 4).previousTick;

  DateTime get startOfYear => DateTime(year);
  DateTime get endOfYear => DateTime(year + 1).previousTick;

  DateTime get previousTick => subtract(const Duration(milliseconds: 1));

  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  bool get isToday => isSameDay(DateTime.now());

  bool get isYesterday =>
      isSameDay(DateTime.now().subtract(const Duration(days: 1)));

  bool isBetween(DateTime start, DateTime end) =>
      !isBefore(start) && !isAfter(end);

  int daysBetween(DateTime other) =>
      startOfDay.difference(other.startOfDay).inDays.abs();

  DateTime addDays(int days) => DateTime(year, month, day + days, hour, minute);

  DateTime addMonths(int months) =>
      DateTime(year, month + months, day, hour, minute);

  DateTime withTime(int hour, int minute) =>
      DateTime(year, month, day, hour, minute);

  /// ISO-8601 week number, used for weekly reviews and heatmap columns.
  int get weekOfYear {
    final thursday = startOfDay.add(Duration(days: 4 - weekday));
    final firstDay = DateTime(thursday.year);
    return ((thursday.difference(firstDay).inDays) / 7).floor() + 1;
  }
}

/// Inclusive list of days in a range — the backbone of heatmaps and streaks.
Iterable<DateTime> daysInRange(DateTime start, DateTime end) sync* {
  var cursor = start.startOfDay;
  final last = end.startOfDay;
  while (!cursor.isAfter(last)) {
    yield cursor;
    cursor = cursor.add(const Duration(days: 1));
  }
}
