import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../services/notifications/notification_service.dart';
import '../../../services/notifications/smart_scheduler.dart';
import 'settings_screen.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    Future<void> pickTime({
      required TimeOfDay initial,
      required ValueChanged<TimeOfDay> onPicked,
    }) async {
      final picked = await showTimePicker(context: context, initialTime: initial);
      if (picked != null) {
        onPicked(picked);
        await ref.read(smartSchedulerProvider).rescheduleAll();
      }
    }

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Notifications'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 80),
          children: <Widget>[
            SettingsGroup(
              title: 'Reminders',
              children: <Widget>[
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('All notifications'),
                  value: settings.notificationsEnabled,
                  onChanged: (value) async {
                    if (value) {
                      final granted = await ref
                          .read(notificationServiceProvider)
                          .requestPermission();
                      if (!(granted.valueOrNull ?? false)) {
                        if (context.mounted) {
                          context.showError(
                            'Notifications are blocked in system settings.',
                          );
                        }
                        return;
                      }
                    }
                    await controller.setNotificationsEnabled(enabled: value);
                    await ref.read(smartSchedulerProvider).rescheduleAll();
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.auto_awesome_rounded),
                  title: const Text('Smart timing'),
                  subtitle: const Text(
                    'Move nudges to the hours you actually use the app',
                  ),
                  value: settings.smartReminderTiming,
                  onChanged: settings.notificationsEnabled
                      ? (value) async {
                          await controller.setSmartReminderTiming(
                            enabled: value,
                          );
                          await ref
                              .read(smartSchedulerProvider)
                              .rescheduleAll();
                        }
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: const Text('Morning briefing'),
                  subtitle: Text(settings.dailyBriefingTime.format(context)),
                  enabled: settings.notificationsEnabled,
                  onTap: () => pickTime(
                    initial: settings.dailyBriefingTime,
                    onPicked: controller.setDailyBriefingTime,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.nights_stay_outlined),
                  title: const Text('Evening reflection'),
                  subtitle:
                      Text(settings.eveningReflectionTime.format(context)),
                  enabled: settings.notificationsEnabled,
                  onTap: () => pickTime(
                    initial: settings.eveningReflectionTime,
                    onPicked: controller.setEveningReflectionTime,
                  ),
                ),
              ],
            ),
            Gap.h16,
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(
                    title: 'What gets scheduled',
                    subtitle: 'Each kind has its own channel, so you can '
                        'silence one without losing the rest',
                  ),
                  for (final channel in ReminderChannel.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: context.colors.onSurfaceVariant,
                          ),
                          Gap.w12,
                          Expanded(
                            child: Text(
                              channel.label,
                              style: context.text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Gap.h12,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final result = await ref
                            .read(smartSchedulerProvider)
                            .rescheduleAll();
                        if (!context.mounted) return;
                        result.fold(
                          (count) =>
                              context.showSnack('$count reminders scheduled'),
                          (failure) => context.showError(failure.message),
                        );
                      },
                      icon: const Icon(Icons.event_repeat_rounded),
                      label: const Text('Rebuild schedule'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
