import 'package:flutter/material.dart';

import '../extensions/context_x.dart';

/// Staggered fade-and-rise used for card grids and list sections.
///
/// Two rules keep this from feeling like a screensaver: the movement is small
/// (12dp) and short (300ms), and it collapses to an instant, motionless build
/// whenever the platform reports "reduce motion". Animation is decoration, so
/// it must never be the thing that makes content appear.
class Entrance extends StatefulWidget {
  const Entrance({
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 45),
    this.duration = const Duration(milliseconds: 300),
    this.offset = 12,
    super.key,
  });

  final Widget child;
  final int index;
  final Duration stagger;
  final Duration duration;
  final double offset;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _controller.value = 1;
    } else {
      Future<void>.delayed(widget.stagger * widget.index, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - _curve.value)),
            child: child,
          ),
        ),
        child: widget.child,
      );
}
