import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/utils/app_logger.dart';
import '../../data/local/table_watcher.dart';
import 'smart_scheduler.dart';

/// Keeps the notification schedule in step with the records it is built from.
///
/// [SmartScheduler] knows how to build the schedule but has no idea when to;
/// left to the settings screen alone, a task created on Monday would never
/// produce a reminder. Mounting this provider — `ref.read(reminderSyncProvider)`
/// during startup — is what connects the two.
final Provider<TableWatcher> reminderSyncProvider = Provider<TableWatcher>(
  (ref) {
    final database = ref.watch(appDatabaseProvider);

    final watcher = TableWatcher(
      database: database,
      // Exactly the tables SmartScheduler reads: tasks and events carry their
      // own reminder times, habits carry a daily one, and people drive the
      // stay-in-touch nudges.
      tables: <ResultSetImplementation<dynamic, dynamic>>[
        database.tasks,
        database.habits,
        database.calendarEvents,
        database.people,
      ],
      debugName: 'reminders',
      // Cancelling and re-registering dozens of platform alarms is not free,
      // and no reminder is so urgent that a minute of staleness matters.
      minimumGap: const Duration(minutes: 1),
      action: () async {
        final result = await ref.read(smartSchedulerProvider).rescheduleAll();
        result.fold(
          (count) => AppLogger.debug('reminders', 'Scheduled $count reminders'),
          (failure) => AppLogger.warn('reminders', failure.message),
        );
      },
    )..start();

    // Turning notifications off has to take effect immediately, not at the
    // next write: rescheduleAll cancels everything when the switch is off.
    ref.listen<bool>(
      settingsProvider.select((s) => s.notificationsEnabled),
      (_, __) => watcher.schedule(),
    );

    ref.onDispose(watcher.dispose);
    return watcher;
  },
);
