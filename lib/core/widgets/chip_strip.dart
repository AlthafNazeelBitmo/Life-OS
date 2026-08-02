import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A horizontally scrolling row of chips that sizes to its content.
///
/// Exists because the obvious version — `SizedBox(height: 44, child:
/// ListView(scrollDirection: horizontal))` — overflows the moment the user
/// raises their system text size: the chips grow, the box does not. Four
/// screens had that bug independently, so the fix lives in one place.
class ChipStrip extends StatelessWidget {
  const ChipStrip({
    required this.children,
    this.padding = Insets.page,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  /// Height to reserve when this has to sit in a slot that demands one, such
  /// as `AppBar.bottom`. Grows with the text scale, and is capped so an extreme
  /// accessibility setting cannot eat the whole screen.
  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return 44 * scale + Gap.sm;
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < children.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  right: i == children.length - 1 ? 0 : Gap.xs,
                ),
                child: children[i],
              ),
          ],
        ),
      );
}
