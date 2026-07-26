import 'package:flutter/material.dart';

import '../extensions/context_x.dart';
import '../theme/app_theme.dart';

/// Soft gradient wash behind glass surfaces.
///
/// Painted with a const-friendly [DecoratedBox] rather than a shader so it
/// costs nothing to keep behind a scrolling list.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({required this.child, this.accent, super.key});

  final Widget child;

  /// Module colour bled into the top-left corner.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.theme.tokens;
    final base = tokens.backdropGradient;
    final colors = accent == null
        ? base
        : <Color>[
            Color.lerp(base.first, accent!, context.isDark ? 0.16 : 0.10)!,
            base.last,
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: child,
    );
  }
}
