import 'package:freezed_annotation/freezed_annotation.dart';

part 'mood_entry.freezed.dart';
part 'mood_entry.g.dart';

/// The six dimensions LifeOS tracks. Kept as an enum so charts, prompts and the
/// correlation engine can iterate them without hard-coded string lists.
enum MoodDimension {
  happiness('Happiness', true),
  energy('Energy', true),
  focus('Focus', true),
  productivity('Productivity', true),
  stress('Stress', false),
  anxiety('Anxiety', false);

  const MoodDimension(this.label, this.higherIsBetter);

  final String label;

  /// Stress and anxiety invert: a low score is a good day.
  final bool higherIsBetter;
}

/// A point-in-time check-in. Values are 1–10.
@freezed
abstract class MoodEntry with _$MoodEntry {
  const factory MoodEntry({
    required String id,
    required DateTime recordedAt,
    required String dayKey,
    @Default(5) int happiness,
    @Default(5) int energy,
    @Default(5) int focus,
    @Default(5) int productivity,
    @Default(5) int stress,
    @Default(5) int anxiety,
    String? note,

    /// Free-form context the user attaches, e.g. `after gym`, `before meeting`.
    @Default(<String>[]) List<String> tags,
    String? journalEntryId,
  }) = _MoodEntry;

  const MoodEntry._();

  factory MoodEntry.fromJson(Map<String, dynamic> json) =>
      _$MoodEntryFromJson(json);

  int valueOf(MoodDimension dimension) => switch (dimension) {
        MoodDimension.happiness => happiness,
        MoodDimension.energy => energy,
        MoodDimension.focus => focus,
        MoodDimension.productivity => productivity,
        MoodDimension.stress => stress,
        MoodDimension.anxiety => anxiety,
      };

  /// Normalised 0–1 where 1 is always "good", inverting the negative
  /// dimensions so they can be averaged together.
  double normalised(MoodDimension dimension) {
    final raw = (valueOf(dimension) - 1) / 9;
    return dimension.higherIsBetter ? raw : 1 - raw;
  }

  /// Single 0–1 wellbeing figure used on the dashboard and in the life score.
  double get overall {
    final total = MoodDimension.values
        .map(normalised)
        .fold<double>(0, (sum, value) => sum + value);
    return total / MoodDimension.values.length;
  }

  String get label => switch (overall) {
        >= 0.8 => 'Great',
        >= 0.65 => 'Good',
        >= 0.45 => 'Okay',
        >= 0.3 => 'Low',
        _ => 'Rough',
      };

  String get emoji => switch (overall) {
        >= 0.8 => '😄',
        >= 0.65 => '🙂',
        >= 0.45 => '😐',
        >= 0.3 => '😕',
        _ => '😣',
      };
}
