import 'dart:ui';

import 'package:flutter/material.dart';

import '../extensions/context_x.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// The surface every dashboard and insight card is built on.
///
/// Glass is a finish, not a requirement: when the theme reports zero blur
/// (high-contrast mode) the widget renders a plain opaque card, so legibility
/// never depends on the effect. The `BackdropFilter` is only mounted when it
/// will actually do something — it is the single most expensive thing on the
/// dashboard, and skipping it keeps scrolling at frame rate on low-end devices.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.padding = Insets.card,
    this.onTap,
    this.accent,
    this.borderRadius = Radii.cardRadius,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Module colour; drawn as a soft wash behind the content.
  final Color? accent;
  final BorderRadius borderRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.theme.tokens;
    final accentColor = accent;

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: tokens.glassFill,
        border: Border.all(color: tokens.glassStroke),
        gradient: accentColor == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  accentColor.withValues(alpha: context.isDark ? 0.22 : 0.14),
                  tokens.glassFill,
                ],
              ),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (tokens.glassBlur > 0) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: tokens.glassBlur,
          sigmaY: tokens.glassBlur,
        ),
        child: surface,
      );
    }

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: tokens.cardShadow,
      ),
      child: ClipRRect(borderRadius: borderRadius, child: surface),
    );

    final tappable = onTap == null
        ? card
        : Stack(
            children: <Widget>[
              card,
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: borderRadius,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          );

    return semanticLabel == null
        ? tappable
        : Semantics(
            label: semanticLabel,
            button: onTap != null,
            container: true,
            child: tappable,
          );
  }
}
