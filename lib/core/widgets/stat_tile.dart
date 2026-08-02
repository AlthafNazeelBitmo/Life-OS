import 'package:flutter/material.dart';

import '../extensions/context_x.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Compact metric readout: label, big value, optional delta and progress.
///
/// The value carries the meaning, so it gets the size; colour is only used for
/// the delta, and it is always paired with an arrow glyph so the direction
/// survives greyscale and colour-blind viewing.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    this.icon,
    this.unit,
    this.delta,
    this.progress,
    this.accent,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? unit;

  /// Change versus the previous comparable period, as a fraction (0.12 = +12%).
  final double? delta;

  /// 0–1 completion, rendered as a slim bar under the value.
  final double? progress;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.theme.tokens;
    final color = accent ?? context.colors.primary;
    final deltaValue = delta;

    return Semantics(
      label: '$label: $value${unit ?? ''}',
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 16, color: color),
                    Gap.w8,
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Gap.h8,
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      value,
                      style: context.text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unit != null) ...<Widget>[
                    Gap.w4,
                    // Flexible: these tiles sit four-across on a small phone,
                    // and a unit like "glasses" is wider than the column.
                    Flexible(
                      child: Text(
                        unit!,
                        style: context.text.labelMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (deltaValue != null) ...<Widget>[
                Gap.h4,
                Row(
                  children: <Widget>[
                    Icon(
                      deltaValue >= 0
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 13,
                      color:
                          deltaValue >= 0 ? tokens.positive : tokens.negative,
                    ),
                    Gap.w4,
                    Flexible(
                      child: Text(
                        '${(deltaValue.abs() * 100).toStringAsFixed(0)}%',
                        style: context.text.labelSmall?.copyWith(
                          color: deltaValue >= 0
                              ? tokens.positive
                              : tokens.negative,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (progress != null) ...<Widget>[
                Gap.h8,
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0.0, 1.0),
                    minHeight: 5,
                    color: color,
                    backgroundColor: context.colors.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
