import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../services/security/biometric_service.dart';
import '../../auth/application/auth_controller.dart';
import 'settings_screen.dart';

class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Privacy and security'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 80),
          children: <Widget>[
            SettingsGroup(
              title: 'App lock',
              children: <Widget>[
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint_rounded),
                  title: const Text('Require biometrics'),
                  subtitle: const Text(
                    'Locks after two minutes in the background',
                  ),
                  value: settings.biometricLock,
                  onChanged: (value) async {
                    if (!value) {
                      await controller.setBiometricLock(enabled: false);
                      return;
                    }
                    // Verify the user can actually pass the gate before turning
                    // it on — otherwise enabling it could lock them out.
                    final service = ref.read(biometricServiceProvider);
                    if (!await service.isAvailable) {
                      if (context.mounted) {
                        context.showError(
                          'This device has no biometrics or PIN set up.',
                        );
                      }
                      return;
                    }
                    final result = await service.authenticate(
                      reason: 'Confirm to enable app lock',
                    );
                    if (result.valueOrNull ?? false) {
                      await controller.setBiometricLock(enabled: true);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded),
                  title: const Text('Lock now'),
                  enabled: settings.biometricLock,
                  onTap: ref.read(authControllerProvider.notifier).lock,
                ),
              ],
            ),
            Gap.h16,
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(title: 'What LifeOS does with your data'),
                  const _Point(
                    icon: Icons.phone_iphone_rounded,
                    text: 'Everything is written to this device first. The app '
                        'is fully usable with no account and no network.',
                  ),
                  const _Point(
                    icon: Icons.cloud_off_rounded,
                    text: 'Cloud sync is optional. With it off, nothing is '
                        'queued for upload at all.',
                  ),
                  const _Point(
                    icon: Icons.auto_awesome_rounded,
                    text: 'AI providers only receive the records needed to '
                        'answer the question you asked — never your whole '
                        'history, and never at all in on-device mode.',
                  ),
                  const _Point(
                    icon: Icons.key_rounded,
                    text: 'API keys live in the platform keychain, not in the '
                        'database, and are excluded from every export.',
                  ),
                  const _Point(
                    icon: Icons.delete_outline_rounded,
                    text: 'Deleting your account wipes local data first, so a '
                        'failed network call cannot leave a copy behind.',
                  ),
                ],
              ),
            ),
            Gap.h16,
            SettingsGroup(
              title: 'Danger zone',
              children: <Widget>[
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_rounded,
                    color: context.colors.error,
                  ),
                  title: const Text('Delete account and all data'),
                  subtitle: const Text('This cannot be undone'),
                  onTap: () => _confirmDelete(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete everything?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Your journal, habits, goals, money and health records will be '
              'permanently removed from this device and from the cloud.\n\n'
              'Type DELETE to confirm.',
            ),
            Gap.h16,
            TextField(controller: controller, autofocus: true),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(controller.text.trim().toUpperCase() == 'DELETE'),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    // Wipes local rows first, then the remote account; see AuthRepositoryImpl.
    final result = await ref.read(authRepositoryProvider).deleteAccount();
    await ref.read(settingsProvider.notifier).reset();
    if (!context.mounted) return;
    result.fold(
      (_) => context.showSnack('Everything has been removed.'),
      (failure) => context.showError(failure.message),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 16, color: context.colors.onSurfaceVariant),
            Gap.w12,
            Expanded(child: Text(text, style: context.text.bodySmall)),
          ],
        ),
      );
}
