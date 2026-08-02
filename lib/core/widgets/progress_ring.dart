import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../extensions/context_x.dart';

/// Circular progress with a label in the middle — used for goal completion,
/// daily habit rings and the life score.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.value,
    this.size = 64,
    this.strokeWidth = 7,
    this.color,
    this.label,
    this.caption,
    super.key,
  });

  /// 0–1.
  final double value;
  final double size;
  final double strokeWidth;
  final Color? color;
  final String? label;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    final ringColor = color ?? context.colors.primary;

    return Semantics(
      label: caption == null ? 'Progress' : '$caption progress',
      value: '${(clamped * 100).round()} percent',
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: clamped),
          duration: context.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, animated, _) => CustomPaint(
            painter: _RingPainter(
              value: animated,
              color: ringColor,
              track: context.colors.surfaceContainerHighest,
              strokeWidth: strokeWidth,
            ),
            child: Center(
              // The ring is a fixed square, so its contents must never dictate
              // its size: a caption like "Running on empty" would otherwise
              // wrap and overflow the bottom.
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: strokeWidth + 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label ?? '${(animated * 100).round()}%',
                      style: context.text.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (caption != null)
                      Text(
                        caption!,
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  final double value;
  final Color color;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = track;

    final valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}
