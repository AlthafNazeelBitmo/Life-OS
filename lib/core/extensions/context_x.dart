import 'package:flutter/material.dart';

import '../theme/breakpoints.dart';

/// Shorthands for the values every widget reaches for.
extension ContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  MediaQueryData get media => MediaQuery.of(this);
  Size get screenSize => MediaQuery.sizeOf(this);
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);
  double get textScale => MediaQuery.textScalerOf(this).scale(1);

  WindowSize get windowSize => Breakpoints.of(screenSize.width);
  bool get isCompact => windowSize == WindowSize.compact;
  bool get isExpanded => windowSize.index >= WindowSize.expanded.index;

  /// Honours the OS "reduce motion" setting — animations must degrade, not
  /// disappear, for users who ask for less movement.
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);

  void showSnack(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void showError(String message) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.errorContainer,
        ),
      );
  }
}
