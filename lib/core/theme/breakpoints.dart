/// Material 3 window size classes.
///
/// LifeOS ships one widget tree for phone, foldable, tablet and desktop; layout
/// decisions branch on these buckets rather than on raw pixel widths.
enum WindowSize {
  /// Phones in portrait — single column, bottom navigation.
  compact,

  /// Large phones landscape / small tablets — two columns, navigation rail.
  medium,

  /// Tablets and small desktop windows — two/three columns, rail.
  expanded,

  /// Desktop — three columns with a persistent navigation drawer.
  large,
}

abstract final class Breakpoints {
  const Breakpoints._();

  static const double medium = 600;
  static const double expanded = 840;
  static const double large = 1240;

  /// Maximum content width so text never stretches into unreadable lines on
  /// wide displays.
  static const double maxContentWidth = 1100;

  static WindowSize of(double width) {
    if (width >= large) return WindowSize.large;
    if (width >= expanded) return WindowSize.expanded;
    if (width >= medium) return WindowSize.medium;
    return WindowSize.compact;
  }

  /// Column count for the dashboard / insights masonry grids.
  static int gridColumns(double width) => switch (of(width)) {
        WindowSize.compact => 1,
        WindowSize.medium => 2,
        WindowSize.expanded => 3,
        WindowSize.large => 4,
      };
}
