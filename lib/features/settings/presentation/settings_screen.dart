import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_provider_type.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/remote/sync_service.dart';
import '../../auth/application/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final user = ref.watch(currentUserProvider);

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Settings'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 80),
          children: <Widget>[
            GlassCard(
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 24,
                    child: Text(
                      user == null || user.displayName.isEmpty
                          ? '👤'
                          : user.displayName[0].toUpperCase(),
                    ),
                  ),
                  Gap.w16,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          user?.displayName.isNotEmpty ?? false
                              ? user!.displayName
                              : 'You',
                          style: context.text.titleSmall,
                        ),
                        Text(
                          user == null
                              ? ''
                              : user.isLocalOnly
                                  ? 'On this device only'
                                  : user.email,
                          style: context.text.labelSmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: ref.read(authControllerProvider.notifier).signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
            Gap.h16,
            _Group(
              title: 'Appearance',
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('Theme'),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const <ButtonSegment<ThemeMode>>[
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                    ],
                    selected: <ThemeMode>{settings.themeMode},
                    onSelectionChanged: (values) =>
                        controller.setThemeMode(values.first),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: const Text('Use wallpaper colours'),
                  subtitle: const Text('Android 12 and newer'),
                  value: settings.useDynamicColor,
                  onChanged: (value) =>
                      controller.setDynamicColor(enabled: value),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.contrast_rounded),
                  title: const Text('High contrast'),
                  subtitle: const Text(
                    'Flat surfaces, stronger separation, no blur',
                  ),
                  value: settings.highContrast,
                  onChanged: (value) =>
                      controller.setHighContrast(enabled: value),
                ),
                ListTile(
                  leading: const Icon(Icons.format_size_rounded),
                  title: const Text('Text size'),
                  subtitle: Slider(
                    value: settings.textScale,
                    min: 0.8,
                    max: 1.6,
                    divisions: 8,
                    label: '${(settings.textScale * 100).round()}%',
                    onChanged: controller.setTextScale,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('Language'),
                  trailing: DropdownButton<String>(
                    value: settings.localeCode,
                    underline: const SizedBox.shrink(),
                    items: <DropdownMenuItem<String>>[
                      for (final entry in Strings.languageNames.entries)
                        DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) controller.setLocale(value);
                    },
                  ),
                ),
              ],
            ),
            Gap.h16,
            _Group(
              title: 'Assistant and data',
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded),
                  title: const Text('AI provider'),
                  subtitle: Text(
                    AiProviderType.fromId(settings.aiProviderId).label,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.settingsAi),
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  subtitle: Text(
                    settings.notificationsEnabled
                        ? 'Briefing at ${Fmt.time(_todayAt(settings.dailyBriefingTime))}'
                        : 'Off',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.settingsNotifications),
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Privacy and security'),
                  subtitle: Text(
                    settings.biometricLock ? 'App lock on' : 'App lock off',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.settingsPrivacy),
                ),
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('Data, export and backup'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.settingsData),
                ),
              ],
            ),
            Gap.h16,
            _Group(
              title: 'Preferences',
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.attach_money_rounded),
                  title: const Text('Currency'),
                  trailing: DropdownButton<String>(
                    value: settings.currency,
                    underline: const SizedBox.shrink(),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: 'USD', child: Text('USD')),
                      DropdownMenuItem<String>(value: 'EUR', child: Text('EUR')),
                      DropdownMenuItem<String>(value: 'GBP', child: Text('GBP')),
                      DropdownMenuItem<String>(value: 'INR', child: Text('INR')),
                      DropdownMenuItem<String>(value: 'JPY', child: Text('JPY')),
                    ],
                    onChanged: (value) {
                      if (value != null) controller.setCurrency(value);
                    },
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.calendar_view_week_rounded),
                  title: const Text('Weeks start on Monday'),
                  value: settings.weekStartsMonday,
                  onChanged: (value) =>
                      controller.setWeekStartsMonday(monday: value),
                ),
              ],
            ),
            Gap.h16,
            const _SyncStatus(),
          ],
        ),
      ),
    );
  }

  static DateTime _todayAt(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              child: SectionHeader(title: title),
            ),
            ...children,
          ],
        ),
      );
}

/// Shows what is waiting to sync. An offline-first app has to be legible about
/// its queue, or users assume their data is lost.
class _SyncStatus extends ConsumerWidget {
  const _SyncStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Sync'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cloud sync'),
            subtitle: Text(
              settings.lastSyncAt == null
                  ? 'Never synced'
                  : 'Last synced ${Fmt.relative(settings.lastSyncAt!)}',
            ),
            value: settings.cloudSyncEnabled,
            onChanged: (value) =>
                ref.read(settingsProvider.notifier).setCloudSync(enabled: value),
          ),
          FutureBuilder<int>(
            future: ref.read(syncServiceProvider).pendingCount(),
            builder: (context, snapshot) => Text(
              snapshot.data == null || snapshot.data == 0
                  ? 'Nothing waiting to upload.'
                  : '${snapshot.data} changes waiting to upload.',
              style: context.text.labelSmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Gap.h8,
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () async {
                final result = await ref.read(syncServiceProvider).syncNow();
                if (!context.mounted) return;
                result.fold(
                  (state) => context.showSnack(
                    state.message ?? 'Sync complete',
                  ),
                  (failure) => context.showError(failure.message),
                );
              },
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sync now'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Re-exported so the sub-screens can share the same grouping shell.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      _Group(title: title, children: children);
}

/// Convenience for sub-screens that need the settings object.
AppSettings settingsOf(WidgetRef ref) => ref.watch(settingsProvider);
