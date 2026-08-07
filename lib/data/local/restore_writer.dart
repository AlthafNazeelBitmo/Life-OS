import '../../core/utils/app_logger.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/finance.dart';
import '../../domain/entities/goal.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/health_metric.dart';
import '../../domain/entities/insight.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/mood_entry.dart';
import '../../domain/entities/person.dart';
import '../../domain/entities/task.dart';
import '../mappers/mappers.dart';
import 'app_database.dart';

/// What a restore actually wrote, per table.
class RestoreSummary {
  const RestoreSummary(this.written, this.skipped);

  /// Rows successfully written, keyed by table.
  final Map<String, int> written;

  /// Rows that could not be parsed, keyed by table. A backup from a slightly
  /// different version should import what it can rather than fail wholesale.
  final Map<String, int> skipped;

  int get total => written.values.fold(0, (sum, count) => sum + count);
  int get totalSkipped => skipped.values.fold(0, (sum, count) => sum + count);
  bool get isEmpty => total == 0;

  @override
  String toString() => 'restored $total rows'
      '${totalSkipped == 0 ? '' : ', skipped $totalSkipped'}';
}

/// Writes a decoded backup or cloud snapshot into the local database.
///
/// Shared by file import and cloud pull, because both receive the same shape:
/// entity JSON produced by `toJson()`. Writing goes straight to Drift rather
/// than through the repositories on purpose — a repository write enqueues a
/// sync operation per row, and restoring a year of history would push tens of
/// thousands of redundant operations into the outbox.
///
/// Every write is `insertOnConflictUpdate` keyed on the record's own id, so
/// importing the same file twice is a no-op rather than a duplicate life.
class RestoreWriter {
  const RestoreWriter(this._db);

  final AppDatabase _db;

  /// Insert order respects the foreign keys declared in `tables.dart`:
  /// attachments need their entry, logs need their habit, milestones need
  /// their goal, interactions need their person.
  static const List<String> tableOrder = <String>[
    'journal_entries',
    'attachments',
    'mood_entries',
    'habits',
    'habit_logs',
    'goals',
    'milestones',
    'tasks',
    'calendar_events',
    'categories',
    'transactions',
    'budgets',
    'savings_goals',
    'health_metrics',
    'people',
    'interactions',
    'insights',
  ];

  Future<RestoreSummary> write(Map<String, List<dynamic>> tables) async {
    final written = <String, int>{};
    final skipped = <String, int>{};

    await _db.transaction(() async {
      for (final table in tableOrder) {
        final rows = tables[table];
        if (rows == null || rows.isEmpty) continue;

        var ok = 0;
        var bad = 0;
        for (final raw in rows) {
          if (raw is! Map<String, dynamic>) {
            bad++;
            continue;
          }
          try {
            await _insert(table, raw);
            ok++;
          } catch (error) {
            // One malformed record must not abandon the whole restore.
            bad++;
            AppLogger.warn('restore', 'Skipped a row in $table', error);
          }
        }
        if (ok > 0) written[table] = ok;
        if (bad > 0) skipped[table] = bad;
      }
    });

    return RestoreSummary(written, skipped);
  }

  Future<void> _insert(String table, Map<String, dynamic> json) async {
    switch (table) {
      case 'journal_entries':
        // Attachments arrive in their own list; the nested copy on the entry
        // would otherwise be written twice.
        await _db.into(_db.journalEntries).insertOnConflictUpdate(
              JournalEntry.fromJson(json)
                  .copyWith(attachments: const <Attachment>[])
                  .toCompanion(),
            );
      case 'attachments':
        await _db
            .into(_db.attachments)
            .insertOnConflictUpdate(Attachment.fromJson(json).toCompanion());
      case 'mood_entries':
        await _db
            .into(_db.moodEntries)
            .insertOnConflictUpdate(MoodEntry.fromJson(json).toCompanion());
      case 'habits':
        await _db
            .into(_db.habits)
            .insertOnConflictUpdate(Habit.fromJson(json).toCompanion());
      case 'habit_logs':
        await _db
            .into(_db.habitLogs)
            .insertOnConflictUpdate(HabitLog.fromJson(json).toCompanion());
      case 'goals':
        await _db.into(_db.goals).insertOnConflictUpdate(
              Goal.fromJson(json)
                  .copyWith(milestones: const <Milestone>[])
                  .toCompanion(),
            );
      case 'milestones':
        await _db
            .into(_db.milestones)
            .insertOnConflictUpdate(Milestone.fromJson(json).toCompanion());
      case 'tasks':
        await _db
            .into(_db.tasks)
            .insertOnConflictUpdate(Task.fromJson(json).toCompanion());
      case 'calendar_events':
        await _db
            .into(_db.calendarEvents)
            .insertOnConflictUpdate(CalendarEvent.fromJson(json).toCompanion());
      case 'categories':
        await _db
            .into(_db.moneyCategories)
            .insertOnConflictUpdate(MoneyCategory.fromJson(json).toCompanion());
      case 'transactions':
        await _db.into(_db.moneyTransactions).insertOnConflictUpdate(
              MoneyTransaction.fromJson(json).toCompanion(),
            );
      case 'budgets':
        await _db
            .into(_db.budgets)
            .insertOnConflictUpdate(Budget.fromJson(json).toCompanion());
      case 'savings_goals':
        await _db
            .into(_db.savingsGoals)
            .insertOnConflictUpdate(SavingsGoal.fromJson(json).toCompanion());
      case 'health_metrics':
        await _db
            .into(_db.healthMetrics)
            .insertOnConflictUpdate(HealthMetric.fromJson(json).toCompanion());
      case 'people':
        await _db
            .into(_db.people)
            .insertOnConflictUpdate(Person.fromJson(json).toCompanion());
      case 'interactions':
        await _db
            .into(_db.interactions)
            .insertOnConflictUpdate(Interaction.fromJson(json).toCompanion());
      case 'insights':
        await _db
            .into(_db.insights)
            .insertOnConflictUpdate(Insight.fromJson(json).toCompanion());
      default:
        throw ArgumentError('Unknown table in backup: $table');
    }
  }
}
