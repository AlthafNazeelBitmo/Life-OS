import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../application/auth_controller.dart';

/// The biometric gate.
///
/// Prompts immediately on open — a lock screen that requires an extra tap to
/// do the thing it exists for is just friction.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _prompting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    setState(() {
      _prompting = true;
      _message = null;
    });

    final ok = await ref.read(authControllerProvider.notifier).unlock();
    if (!mounted) return;
    setState(() {
      _prompting = false;
      _message = ok ? null : 'Not recognised. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AppBackdrop(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.lock_rounded,
                  size: 56,
                  color: context.colors.primary,
                ),
                Gap.h24,
                Text('LifeOS is locked', style: context.text.titleLarge),
                Gap.h8,
                Text(
                  _message ?? 'Unlock to continue',
                  style: context.text.bodyMedium?.copyWith(
                    color: _message == null
                        ? context.colors.onSurfaceVariant
                        : context.colors.error,
                  ),
                ),
                Gap.h32,
                FilledButton.icon(
                  onPressed: _prompting ? null : _unlock,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Unlock'),
                ),
                Gap.h8,
                TextButton(
                  onPressed: ref.read(authControllerProvider.notifier).signOut,
                  child: const Text('Sign out instead'),
                ),
              ],
            ),
          ),
        ),
      );
}
