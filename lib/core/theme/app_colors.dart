import 'package:flutter/material.dart';

/// Brand palette and per-module accents.
///
/// The Material 3 scheme is generated from [seed]; these extra colours cover
/// things a scheme cannot express — module identity, mood ramps, chart series.
abstract final class AppColors {
  const AppColors._();

  static const Color seed = Color(0xFF5B5BD6); // indigo-violet
  static const Color positive = Color(0xFF17A673);
  static const Color caution = Color(0xFFE0A100);
  static const Color negative = Color(0xFFE5484D);

  /// Module accents — kept distinguishable in both themes and for the most
  /// common colour-vision deficiencies (checked against deuteranopia).
  static const Color journal = Color(0xFF7C5CFF);
  static const Color mood = Color(0xFFEC6B9B);
  static const Color habits = Color(0xFF17A673);
  static const Color goals = Color(0xFFF08C3A);
  static const Color tasks = Color(0xFF3B82F6);
  static const Color calendar = Color(0xFF06A6C1);
  static const Color finance = Color(0xFF12B886);
  static const Color health = Color(0xFFE5484D);
  static const Color insights = Color(0xFF8B5CF6);
  static const Color people = Color(0xFFD97757);

  /// Ordered categorical series for charts. Read as one system rather than a
  /// rainbow: same lightness band, rotating hue.
  static const List<Color> chartSeries = <Color>[
    Color(0xFF5B5BD6),
    Color(0xFF12B886),
    Color(0xFFF08C3A),
    Color(0xFFEC6B9B),
    Color(0xFF06A6C1),
    Color(0xFF8B5CF6),
    Color(0xFFE5484D),
    Color(0xFF6B7280),
  ];

  /// Sequential ramp for habit heatmaps (empty → fully complete).
  static const List<Color> heatRamp = <Color>[
    Color(0xFFE9ECF2),
    Color(0xFFBFE3D2),
    Color(0xFF7FCBAC),
    Color(0xFF35A97F),
    Color(0xFF17784F),
  ];

  static const List<Color> heatRampDark = <Color>[
    Color(0xFF23262E),
    Color(0xFF1E4838),
    Color(0xFF246B4D),
    Color(0xFF2E9A6C),
    Color(0xFF52D6A0),
  ];

  /// Diverging ramp for mood: low (red) → neutral → high (green).
  static const List<Color> moodRamp = <Color>[
    Color(0xFFE5484D),
    Color(0xFFF08C3A),
    Color(0xFFE0C000),
    Color(0xFF7FCBAC),
    Color(0xFF17A673),
  ];

  static Color forScore(double score01) {
    final clamped = score01.clamp(0.0, 1.0);
    final scaled = clamped * (moodRamp.length - 1);
    final index = scaled.floor().clamp(0, moodRamp.length - 2);
    return Color.lerp(moodRamp[index], moodRamp[index + 1], scaled - index)!;
  }
}
