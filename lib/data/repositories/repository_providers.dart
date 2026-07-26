import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cache/key_value_store.dart';
import '../../core/di/core_providers.dart';
import '../../core/settings/settings_controller.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/repositories/finance_repository.dart';
import '../../domain/repositories/goal_repository.dart';
import '../../domain/repositories/habit_repository.dart';
import '../../domain/repositories/health_repository.dart';
import '../../domain/repositories/insight_repository.dart';
import '../../domain/repositories/journal_repository.dart';
import '../../domain/repositories/mood_repository.dart';
import '../../domain/repositories/people_repository.dart';
import '../../domain/repositories/search_repository.dart';
import '../../domain/repositories/task_repository.dart';
import '../../domain/repositories/timeline_repository.dart';
import '../remote/sync_queue_writer.dart';
import 'auth_repository_impl.dart';
import 'calendar_repository_impl.dart';
import 'chat_repository_impl.dart';
import 'finance_repository_impl.dart';
import 'goal_repository_impl.dart';
import 'habit_repository_impl.dart';
import 'health_repository_impl.dart';
import 'insight_repository_impl.dart';
import 'journal_repository_impl.dart';
import 'mood_repository_impl.dart';
import 'people_repository_impl.dart';
import 'search_repository_impl.dart';
import 'task_repository_impl.dart';
import 'timeline_repository_impl.dart';

/// Every repository is exposed as its *interface*, never its implementation.
///
/// Feature code depends only on the abstractions in `domain/repositories`, so a
/// test can swap in a fake with a single `overrideWithValue` and nothing else
/// in the tree notices.

final Provider<SyncQueueWriter> syncQueueWriterProvider =
    Provider<SyncQueueWriter>((ref) {
  // In local-only mode nothing is queued at all — no shadow copy of the user's
  // data accumulates for a backend they never opted into.
  final cloudEnabled = ref.watch(
    settingsProvider.select((s) => s.cloudSyncEnabled),
  );
  return SyncQueueWriter(
    ref.watch(appDatabaseProvider),
    enabled: cloudEnabled,
  );
});

final Provider<JournalRepository> journalRepositoryProvider =
    Provider<JournalRepository>(
  (ref) => JournalRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueWriterProvider),
  ),
);

final Provider<MoodRepository> moodRepositoryProvider = Provider<MoodRepository>(
  (ref) => MoodRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueWriterProvider),
  ),
);

final Provider<HabitRepository> habitRepositoryProvider =
    Provider<HabitRepository>(
  (ref) => HabitRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueWriterProvider),
  ),
);

final Provider<GoalRepository> goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueWriterProvider),
  ),
);

final Provider<TaskRepository> taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueWriterProvider),
  ),
);

final Provider<CalendarRepository> calendarRepositoryProvider =
    Provider<CalendarRepository>(
  (ref) => CalendarRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueWriterProvider),
  ),
);

final Provider<FinanceRepository> financeRepositoryProvider =
    Provider<FinanceRepository>(
  (ref) => FinanceRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueWriterProvider),
  ),
);

final Provider<HealthRepository> healthRepositoryProvider =
    Provider<HealthRepository>(
  (ref) => HealthRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueWriterProvider),
  ),
);

final Provider<PeopleRepository> peopleRepositoryProvider =
    Provider<PeopleRepository>(
  (ref) => PeopleRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueWriterProvider),
  ),
);

final Provider<ChatRepository> chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final Provider<InsightRepository> insightRepositoryProvider =
    Provider<InsightRepository>(
  (ref) => InsightRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final Provider<TimelineRepository> timelineRepositoryProvider =
    Provider<TimelineRepository>(
  (ref) => TimelineRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final Provider<SearchRepository> searchRepositoryProvider =
    Provider<SearchRepository>(
  (ref) => SearchRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>(
  (ref) {
    final repository = AuthRepositoryImpl(
      ref.watch(keyValueStoreProvider),
      ref.watch(appDatabaseProvider),
    );
    ref.onDispose(repository.dispose);
    return repository;
  },
);

/// Concrete type, needed by the lock screen for `lock()` / `unlock()`, which
/// are app-lifecycle concerns rather than part of the auth contract.
final Provider<AuthRepositoryImpl> authRepositoryImplProvider =
    Provider<AuthRepositoryImpl>(
  (ref) => ref.watch(authRepositoryProvider) as AuthRepositoryImpl,
);

/// Convenience for widgets that only need to know the store exists.
final Provider<KeyValueStore> cacheProvider =
    Provider<KeyValueStore>((ref) => ref.watch(keyValueStoreProvider));
