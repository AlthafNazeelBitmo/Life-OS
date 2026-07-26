import 'package:intl/intl.dart';

/// Display formatting helpers shared by every module.
///
/// Money is stored as integer minor units (cents) everywhere in LifeOS —
/// doubles are never used for currency — so all conversion to a readable string
/// happens here.
abstract final class Fmt {
  const Fmt._();

  static final DateFormat _dayMonth = DateFormat('EEEE, d MMMM');
  static final DateFormat _shortDate = DateFormat('d MMM y');
  static final DateFormat _monthYear = DateFormat('MMMM y');
  static final DateFormat _time = DateFormat.jm();
  static final DateFormat _weekday = DateFormat('EEE');

  static String longDate(DateTime d) => _dayMonth.format(d);
  static String shortDate(DateTime d) => _shortDate.format(d);
  static String monthYear(DateTime d) => _monthYear.format(d);
  static String time(DateTime d) => _time.format(d);
  static String weekday(DateTime d) => _weekday.format(d);

  static String money(int minorUnits, {String currency = 'USD'}) {
    final format = NumberFormat.simpleCurrency(name: currency);
    return format.format(minorUnits / 100);
  }

  /// Compact form for chart labels and dense cards: `$1.2k`.
  static String compactMoney(int minorUnits, {String currency = 'USD'}) {
    final format = NumberFormat.compactSimpleCurrency(name: currency);
    return format.format(minorUnits / 100);
  }

  static String percent(double fraction, {int decimals = 0}) =>
      '${(fraction * 100).toStringAsFixed(decimals)}%';

  static String duration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  /// Hours with one decimal, e.g. sleep `7.5h`.
  static String hours(double value) => '${value.toStringAsFixed(1)}h';

  static String relative(DateTime when, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(when);
    if (diff.inSeconds.abs() < 60) return 'just now';
    if (diff.isNegative) {
      final ahead = diff.abs();
      if (ahead.inMinutes < 60) return 'in ${ahead.inMinutes}m';
      if (ahead.inHours < 24) return 'in ${ahead.inHours}h';
      return 'in ${ahead.inDays}d';
    }
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return shortDate(when);
  }

  /// `2026-07-26` — the canonical day key used by every table that buckets
  /// records by calendar day.
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime parseDayKey(String key) => DateTime.parse(key);

  /// `2026-07` — month bucket for budgets and monthly reviews.
  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
}
