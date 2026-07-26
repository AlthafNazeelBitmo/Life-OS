import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Extra design tokens that a [ColorScheme] cannot express.
///
/// Exposed as a [ThemeExtension] so widgets read them the same way they read
/// anything else from the theme, and so high-contrast variants can override
/// them wholesale.
@immutable
class LifeOsTokens extends ThemeExtension<LifeOsTokens> {
  const LifeOsTokens({
    required this.glassFill,
    required this.glassStroke,
    required this.glassBlur,
    required this.cardShadow,
    required this.heatRamp,
    required this.positive,
    required this.caution,
    required this.negative,
    required this.backdropGradient,
  });

  final Color glassFill;
  final Color glassStroke;
  final double glassBlur;
  final List<BoxShadow> cardShadow;
  final List<Color> heatRamp;
  final Color positive;
  final Color caution;
  final Color negative;
  final List<Color> backdropGradient;

  static LifeOsTokens light() => LifeOsTokens(
        glassFill: Colors.white.withValues(alpha: 0.66),
        glassStroke: Colors.white.withValues(alpha: 0.72),
        glassBlur: 18,
        cardShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF0B1020).withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        heatRamp: AppColors.heatRamp,
        positive: AppColors.positive,
        caution: AppColors.caution,
        negative: AppColors.negative,
        backdropGradient: const <Color>[Color(0xFFF6F5FF), Color(0xFFEFF7F6)],
      );

  static LifeOsTokens dark() => LifeOsTokens(
        glassFill: const Color(0xFF14161C).withValues(alpha: 0.62),
        glassStroke: Colors.white.withValues(alpha: 0.10),
        glassBlur: 22,
        cardShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
        heatRamp: AppColors.heatRampDark,
        positive: const Color(0xFF3DD68C),
        caution: const Color(0xFFF5C451),
        negative: const Color(0xFFFF6369),
        backdropGradient: const <Color>[Color(0xFF0C0D12), Color(0xFF11151B)],
      );

  /// Flat, opaque, high-contrast variant used when the OS asks for it or the
  /// user enables it in Settings › Accessibility.
  LifeOsTokens toHighContrast(ColorScheme scheme) => LifeOsTokens(
        glassFill: scheme.surface,
        glassStroke: scheme.outline,
        glassBlur: 0,
        cardShadow: const <BoxShadow>[],
        heatRamp: heatRamp,
        positive: positive,
        caution: caution,
        negative: negative,
        backdropGradient: <Color>[scheme.surface, scheme.surface],
      );

  @override
  LifeOsTokens copyWith({
    Color? glassFill,
    Color? glassStroke,
    double? glassBlur,
    List<BoxShadow>? cardShadow,
    List<Color>? heatRamp,
    Color? positive,
    Color? caution,
    Color? negative,
    List<Color>? backdropGradient,
  }) =>
      LifeOsTokens(
        glassFill: glassFill ?? this.glassFill,
        glassStroke: glassStroke ?? this.glassStroke,
        glassBlur: glassBlur ?? this.glassBlur,
        cardShadow: cardShadow ?? this.cardShadow,
        heatRamp: heatRamp ?? this.heatRamp,
        positive: positive ?? this.positive,
        caution: caution ?? this.caution,
        negative: negative ?? this.negative,
        backdropGradient: backdropGradient ?? this.backdropGradient,
      );

  @override
  LifeOsTokens lerp(covariant LifeOsTokens? other, double t) {
    if (other == null) return this;
    return LifeOsTokens(
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassStroke: Color.lerp(glassStroke, other.glassStroke, t)!,
      glassBlur: glassBlur + (other.glassBlur - glassBlur) * t,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      heatRamp: t < 0.5 ? heatRamp : other.heatRamp,
      positive: Color.lerp(positive, other.positive, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      backdropGradient: t < 0.5 ? backdropGradient : other.backdropGradient,
    );
  }
}

/// Builds the two app themes.
///
/// `dynamicScheme` carries Android 12+ wallpaper colours when the user opts in;
/// otherwise the palette is seeded from [AppColors.seed].
abstract final class AppTheme {
  const AppTheme._();

  static ThemeData light({
    ColorScheme? dynamicScheme,
    bool highContrast = false,
  }) =>
      _build(
        scheme: dynamicScheme ??
            ColorScheme.fromSeed(
              seedColor: AppColors.seed,
              contrastLevel: highContrast ? 1.0 : 0.0,
            ),
        tokens: LifeOsTokens.light(),
        highContrast: highContrast,
      );

  static ThemeData dark({
    ColorScheme? dynamicScheme,
    bool highContrast = false,
  }) =>
      _build(
        scheme: dynamicScheme ??
            ColorScheme.fromSeed(
              seedColor: AppColors.seed,
              brightness: Brightness.dark,
              contrastLevel: highContrast ? 1.0 : 0.0,
            ),
        tokens: LifeOsTokens.dark(),
        highContrast: highContrast,
      );

  static ThemeData _build({
    required ColorScheme scheme,
    required LifeOsTokens tokens,
    required bool highContrast,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    final baseText = isDark ? Typography.whiteMountainView : Typography.blackMountainView;
    final textTheme = GoogleFonts.interTextTheme(baseText).copyWith(
      displaySmall: GoogleFonts.instrumentSerif(
        textStyle: baseText.displaySmall,
        fontWeight: FontWeight.w400,
      ),
      headlineMedium: GoogleFonts.inter(
        textStyle: baseText.headlineMedium,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      titleLarge: GoogleFonts.inter(
        textStyle: baseText.titleLarge,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      labelLarge: GoogleFonts.inter(
        textStyle: baseText.labelLarge,
        fontWeight: FontWeight.w600,
      ),
    );

    final effectiveTokens =
        highContrast ? tokens.toHighContrast(scheme) : tokens;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      extensions: <ThemeExtension<dynamic>>[effectiveTokens],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0.5,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardRadius),
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerHighest,
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorShape: const StadiumBorder(),
        labelType: NavigationRailLabelType.all,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetRadius),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: Radii.cardRadius),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        year2023: false,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}

/// `theme.tokens` reads nicer than the generic extension lookup at call sites.
extension ThemeTokensX on ThemeData {
  LifeOsTokens get tokens => extension<LifeOsTokens>() ?? LifeOsTokens.light();
}
