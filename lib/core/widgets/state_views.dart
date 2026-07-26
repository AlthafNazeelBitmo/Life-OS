import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../error/failures.dart';
import '../extensions/context_x.dart';
import '../theme/app_spacing.dart';

/// Skeleton placeholder. Preferred over a spinner for content that has a known
/// shape — it keeps the layout from jumping when data lands.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    this.height = 16,
    this.width = double.infinity,
    this.radius = Radii.sm,
    super.key,
  });

  final double height;
  final double width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    // Respecting "reduce motion" happens in build; the controller is cheap and
    // simply left idle in that case.
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.surfaceContainerHighest;
    if (context.reduceMotion) {
      return _box(base);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _box(
        Color.lerp(base, context.colors.surfaceContainer, _controller.value)!,
      ),
    );
  }

  Widget _box(Color color) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            if (label != null) ...<Widget>[
              Gap.h16,
              Text(label!, style: context.text.bodyMedium),
            ],
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 44, color: context.colors.outline),
              Gap.h16,
              Text(
                title,
                style: context.text.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...<Widget>[
                Gap.h8,
                Text(
                  message!,
                  style: context.text.bodyMedium
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...<Widget>[Gap.h24, action!],
            ],
          ),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({required this.failure, this.onRetry, super.key});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: context.colors.error,
              ),
              Gap.h16,
              Text(
                failure.message,
                style: context.text.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (failure.isRetryable && onRetry != null) ...<Widget>[
                Gap.h16,
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      );
}

/// Renders an [AsyncValue] with consistent loading/error treatment.
///
/// Riverpod keeps the previous value around while refreshing; this honours that
/// by showing stale data rather than flashing a spinner on every rebuild.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    required this.value,
    required this.builder,
    this.loading,
    this.onRetry,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) {
      return builder(context, value.requireValue);
    }
    return value.when(
      data: (data) => builder(context, data),
      loading: () => loading ?? const LoadingView(),
      error: (error, stackTrace) => ErrorView(
        failure: error is Failure
            ? error
            : UnknownFailure(cause: error, stackTrace: stackTrace),
        onRetry: onRetry,
      ),
    );
  }
}
