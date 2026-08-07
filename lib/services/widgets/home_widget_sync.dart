import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../../core/utils/app_logger.dart';
import '../../data/local/table_watcher.dart';
import 'home_widget_service.dart';

/// Keeps the home-screen widgets showing what the app shows.
///
/// A widget that lags behind is worse than no widget: the user trusts the
/// number on their home screen precisely because they never opened the app to
/// check it. Mounting this provider during startup is what keeps it honest.
final Provider<TableWatcher> homeWidgetSyncProvider = Provider<TableWatcher>(
  (ref) {
    final database = ref.watch(appDatabaseProvider);

    final watcher = TableWatcher(
      database: database,
      // Every table HomeWidgetService.refresh reads.
      tables: <ResultSetImplementation<dynamic, dynamic>>[
        database.tasks,
        database.habits,
        database.habitLogs,
        database.moodEntries,
        database.calendarEvents,
        database.moneyTransactions,
      ],
      debugName: 'widgets',
      minimumGap: const Duration(seconds: 15),
      action: () async {
        final result = await ref.read(homeWidgetServiceProvider).refresh();
        result.fold(
          (_) {},
          (failure) => AppLogger.debug('widgets', failure.message),
        );
      },
    )..start();

    ref.onDispose(watcher.dispose);
    return watcher;
  },
);
