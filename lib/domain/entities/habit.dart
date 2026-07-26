import 'package:freezed_annotation/freezed_annotation.dart';

import 'recurrence.dart';

part 'habit.freezed.dart';
part 'habit.g.dart';

enum HabitCadence { daily, weekly, monthly, custom }

/// Some habits are yes/no ("meditate"), others accumulate ("drink 8 glasses").
enum HabitKind { binary, quantity }

@freezed
abstract class Habit with _$Habit {
  const factory Habit({
    required String id,
    required String name,
    required DateTime createdAt,
    @Default('✅') String emoji,

    /// ARGB int so it round-trips through SQLite without a converter.
    @Default(0xFF17A673) int colorValue,
    @Default(HabitCadence.daily) HabitCadence cadence,
    @Default(HabitKind.binary) HabitKind kind,

    /// For [HabitKind.quantity]: how many units count as done in one period.
    @Default(1) int target,
    @Default('') String unit,

    /// Used when [cadence] is [HabitCadence.custom].
    Recurrence? customSchedule,

    /// Minutes past midnight for the reminder, null to disable.
    int? reminderMinutes,
    @Default('') String notes,

    /// Optional link to the goal this habit serves.
    String? goalId,
    DateTime? archivedAt,
  }) = _Habit;

  const Habit._();

  factory Habit.fromJson(Map<String, dynamic> json) => _$HabitFromJson(json);

  bool get isArchived => archivedAt != null;

  /// Whether the habit is expected on [date].
  bool isScheduledOn(DateTime date) => switch (cadence) {
        HabitCadence.daily => true,
        HabitCadence.weekly => date.weekday == createdAt.weekday,
        HabitCadence.monthly => date.day == createdAt.day,
        HabitCadence.custom =>
          customSchedule?.occursOn(date, anchor: createdAt) ?? true,
      };
}

@freezed
abstract class HabitLog with _$HabitLog {
  const factory HabitLog({
    required String id,
    required String habitId,
    required String dayKey,
    required DateTime recordedAt,

    /// 1 for a completed binary habit, or the amount for quantity habits.
    @Default(1) int value,
    String? note,
  }) = _HabitLog;

  factory HabitLog.fromJson(Map<String, dynamic> json) =>
      _$HabitLogFromJson(json);
}

/// Derived analytics for a habit over a window. Computed in the repository, not
/// stored, so it can never go stale.
@freezed
abstract class HabitStats with _$HabitStats {
  const factory HabitStats({
    required String habitId,
    @Default(0) int currentStreak,
    @Default(0) int longestStreak,

    /// 0–1 over the analysed window.
    @Default(0) double completionRate,
    @Default(0) int totalCompletions,

    /// 0–100 blend of consistency, recency and streak length.
    @Default(0) int score,

    /// dayKey → amount completed, for the heatmap.
    @Default(<String, int>{}) Map<String, int> heatmap,
  }) = _HabitStats;

  const HabitStats._();

  factory HabitStats.fromJson(Map<String, dynamic> json) =>
      _$HabitStatsFromJson(json);

  String get grade => switch (score) {
        >= 90 => 'Excellent',
        >= 75 => 'Strong',
        >= 55 => 'Building',
        >= 30 => 'Shaky',
        _ => 'Needs a restart',
      };
}

/// An AI proposal the user can accept into a real habit.
@freezed
abstract class HabitSuggestion with _$HabitSuggestion {
  const factory HabitSuggestion({
    required String name,
    required String rationale,
    @Default('✨') String emoji,
    @Default(HabitCadence.daily) HabitCadence cadence,
    @Default(1) int target,
    @Default('') String unit,

    /// Ids of the journal entries, moods or goals that motivated the
    /// suggestion. Surfaced as "why am I seeing this?".
    @Default(<String>[]) List<String> basedOn,
  }) = _HabitSuggestion;

  factory HabitSuggestion.fromJson(Map<String, dynamic> json) =>
      _$HabitSuggestionFromJson(json);
}
