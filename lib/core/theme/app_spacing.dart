import 'package:flutter/widgets.dart';

/// 4pt spacing scale. Every gap in the app is one of these values.
abstract final class Gap {
  const Gap._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  static const SizedBox h4 = SizedBox(height: xs);
  static const SizedBox h8 = SizedBox(height: sm);
  static const SizedBox h12 = SizedBox(height: md);
  static const SizedBox h16 = SizedBox(height: lg);
  static const SizedBox h24 = SizedBox(height: xl);
  static const SizedBox h32 = SizedBox(height: xxl);

  static const SizedBox w4 = SizedBox(width: xs);
  static const SizedBox w8 = SizedBox(width: sm);
  static const SizedBox w12 = SizedBox(width: md);
  static const SizedBox w16 = SizedBox(width: lg);
  static const SizedBox w24 = SizedBox(width: xl);
}

/// Corner radii. LifeOS uses generous, consistent rounding for its card-heavy
/// surfaces.
abstract final class Radii {
  const Radii._();

  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius sheetRadius =
      BorderRadius.vertical(top: Radius.circular(xl));
  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(pill));
}

/// Standard page padding, tightened on phones and relaxed on wide windows.
abstract final class Insets {
  const Insets._();

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: Gap.lg);
  static const EdgeInsets card = EdgeInsets.all(Gap.lg);
  static const EdgeInsets cardCompact = EdgeInsets.all(Gap.md);
  static const EdgeInsets sheet =
      EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, Gap.xl);

  /// Leaves room for the floating assistant button at the bottom of scrollers.
  static const EdgeInsets listBottom = EdgeInsets.only(bottom: 120);
}
