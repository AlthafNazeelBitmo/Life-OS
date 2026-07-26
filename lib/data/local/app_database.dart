import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/utils/app_logger.dart';
import '../../domain/entities/finance.dart' show TransactionType;
import 'tables.dart';

part 'app_database.g.dart';

/// The single local SQLite database.
///
/// LifeOS is offline-first: this file is the source of truth, and the cloud is
/// a replica of it rather than the other way round. Every screen reads from a
/// Drift stream, so a write in one module repaints every dependent view without
/// any manual invalidation.
@DriftDatabase(
  tables: <Type>[
    JournalEntries,
    Attachments,
    MoodEntries,
    Habits,
    HabitLogs,
    Goals,
    Milestones,
    Tasks,
    CalendarEvents,
    MoneyCategories,
    MoneyTransactions,
    Budgets,
    SavingsGoals,
    HealthMetrics,
    HealthTargets,
    People,
    Interactions,
    ChatThreads,
    ChatMessages,
    Insights,
    PeriodReviews,
    LifeScores,
    SearchDocs,
    RecentQueries,
    SyncQueue,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory instance for tests. Every repository test builds one of these,
  /// which is why the repositories take an [AppDatabase] rather than reaching
  /// for a singleton.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (m, from, to) async {
          // Migration steps land here as the schema evolves. Drift's
          // `make-migrations` verifier keeps this honest; see
          // docs/DATABASE_SCHEMA.md for the workflow.
          AppLogger.info('db', 'Migrating schema $from → $to');
          await _createIndexes();
        },
        beforeOpen: (details) async {
          // Required for the ON DELETE CASCADE relations above; SQLite has
          // foreign keys off by default and it is a per-connection setting.
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
          if (details.wasCreated) {
            await _seedSystemCategories();
          }
        },
      );

  /// Indexes for the access patterns the app actually has: "by day",
  /// "by range", "most recent first".
  Future<void> _createIndexes() async {
    const statements = <String>[
      'CREATE INDEX IF NOT EXISTS idx_journal_day ON journal_entries (day_key)',
      'CREATE INDEX IF NOT EXISTS idx_journal_created ON journal_entries (created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_mood_day ON mood_entries (day_key)',
      'CREATE INDEX IF NOT EXISTS idx_habitlog_habit_day ON habit_logs (habit_id, day_key)',
      'CREATE INDEX IF NOT EXISTS idx_task_status ON tasks (status, order_index)',
      'CREATE INDEX IF NOT EXISTS idx_task_due ON tasks (due_at)',
      'CREATE INDEX IF NOT EXISTS idx_event_range ON calendar_events (starts_at, ends_at)',
      'CREATE INDEX IF NOT EXISTS idx_txn_date ON money_transactions (occurred_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_txn_category ON money_transactions (category_id)',
      'CREATE INDEX IF NOT EXISTS idx_health_day ON health_metrics (day_key, kind)',
      'CREATE INDEX IF NOT EXISTS idx_chat_thread ON chat_messages (thread_id, created_at)',
      'CREATE INDEX IF NOT EXISTS idx_search_source ON search_docs (source, occurred_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_interactions_person ON interactions (person_id, occurred_at DESC)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  /// A brand-new database still needs somewhere to put an expense, so the
  /// starter categories ship with it.
  Future<void> _seedSystemCategories() async {
    const seeds = <List<Object>>[
      <Object>['cat_food', 'Food & Drink', '🍜', 0xFFF08C3A],
      <Object>['cat_transport', 'Transport', '🚕', 0xFF3B82F6],
      <Object>['cat_home', 'Home', '🏠', 0xFF8B5CF6],
      <Object>['cat_health', 'Health', '💊', 0xFFE5484D],
      <Object>['cat_fun', 'Fun', '🎬', 0xFFEC6B9B],
      <Object>['cat_shopping', 'Shopping', '🛍️', 0xFF06A6C1],
      <Object>['cat_bills', 'Bills', '🧾', 0xFF6B7280],
      <Object>['cat_income', 'Income', '💰', 0xFF12B886],
    ];

    await batch((batch) {
      batch.insertAll(
        moneyCategories,
        <Insertable<MoneyCategoryRow>>[
          for (final seed in seeds)
            MoneyCategoriesCompanion.insert(
              id: seed[0]! as String,
              name: seed[1]! as String,
              emoji: Value(seed[2]! as String),
              colorValue: Value(seed[3]! as int),
              kind: seed[0] == 'cat_income'
                  ? TransactionType.income
                  : TransactionType.expense,
              isSystem: const Value(true),
            ),
        ],
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// Wipes user data while keeping the schema. Backs "Delete all data" in
  /// Settings › Privacy and the sign-out-of-a-shared-device path.
  Future<void> wipe() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
    await _seedSystemCategories();
  }
}

/// Opens the on-device file.
///
/// `drift_flutter` runs the database on a background isolate, so large reads
/// (a year of habit logs for a heatmap) never block the UI thread. To encrypt
/// the file at rest, swap `sqlite3_flutter_libs` for `sqlcipher_flutter_libs`
/// and pass the key from `SecureStore` here — see docs/DEPLOYMENT.md.
QueryExecutor _openConnection() => driftDatabase(name: 'lifeos');
