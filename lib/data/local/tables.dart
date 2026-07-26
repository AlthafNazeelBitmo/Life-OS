import 'package:drift/drift.dart';

import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/finance.dart';
import '../../domain/entities/goal.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/health_metric.dart';
import '../../domain/entities/insight.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/person.dart';
import '../../domain/entities/task.dart';
import 'converters.dart';

/// Drift table definitions.
///
/// Conventions used everywhere below:
///  * `id` is a client-generated UUID v7 text primary key, so records can be
///    created offline and merged without renumbering.
///  * timestamps are stored as UTC `DateTime`; `dayKey` (`yyyy-MM-dd`) carries
///    the *local* calendar day, because "did I journal today?" is a wall-clock
///    question, not a UTC one.
///  * money is `int` minor units.
///  * user-visible deletes are soft (`deletedAt`) so sync can propagate them.
///  * row classes get a `Row` suffix to keep them clearly distinct from the
///    domain entities they map to.

@DataClassName('JournalEntryRow')
class JournalEntries extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get dayKey => text().withLength(min: 10, max: 10)();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get tags =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get peopleIds =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get location =>
      text().nullable().map(const GeoPointConverter())();
  TextColumn get weather => text().nullable()();
  IntColumn get moodScore => integer().nullable()();
  TextColumn get analysis => text().nullable().map(const AnalysisConverter())();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('AttachmentRow')
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get entryId =>
      text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<AttachmentKind>()();
  TextColumn get localPath => text()();
  TextColumn get remoteUrl => text().nullable()();
  TextColumn get caption => text().nullable()();
  TextColumn get transcript => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('MoodEntryRow')
class MoodEntries extends Table {
  TextColumn get id => text()();
  DateTimeColumn get recordedAt => dateTime()();
  TextColumn get dayKey => text().withLength(min: 10, max: 10)();
  IntColumn get happiness => integer().withDefault(const Constant(5))();
  IntColumn get energy => integer().withDefault(const Constant(5))();
  IntColumn get focus => integer().withDefault(const Constant(5))();
  IntColumn get productivity => integer().withDefault(const Constant(5))();
  IntColumn get stress => integer().withDefault(const Constant(5))();
  IntColumn get anxiety => integer().withDefault(const Constant(5))();
  TextColumn get note => text().nullable()();
  TextColumn get tags =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get journalEntryId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('HabitRow')
class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get emoji => text().withDefault(const Constant('✅'))();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFF17A673))();
  TextColumn get cadence => textEnum<HabitCadence>()();
  TextColumn get kind => textEnum<HabitKind>()();
  IntColumn get target => integer().withDefault(const Constant(1))();
  TextColumn get unit => text().withDefault(const Constant(''))();
  TextColumn get customSchedule =>
      text().nullable().map(const RecurrenceConverter())();
  IntColumn get reminderMinutes => integer().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get goalId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('HabitLogRow')
class HabitLogs extends Table {
  TextColumn get id => text()();
  TextColumn get habitId =>
      text().references(Habits, #id, onDelete: KeyAction.cascade)();
  TextColumn get dayKey => text().withLength(min: 10, max: 10)();
  DateTimeColumn get recordedAt => dateTime()();
  IntColumn get value => integer().withDefault(const Constant(1))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  /// One row per habit per day: logging twice updates the amount instead of
  /// creating a duplicate, which is what makes streak maths reliable.
  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
        <Column<Object>>{habitId, dayKey},
      ];
}

@DataClassName('GoalRow')
class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get horizon => textEnum<GoalHorizon>()();
  TextColumn get status => textEnum<GoalStatus>()();
  TextColumn get category => text().withDefault(const Constant(''))();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFFF08C3A))();
  DateTimeColumn get targetDate => dateTime().nullable()();
  RealColumn get manualProgress => real().nullable()();
  TextColumn get habitIds =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get achievedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('MilestoneRow')
class Milestones extends Table {
  TextColumn get id => text()();
  TextColumn get goalId =>
      text().references(Goals, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get parentId => text().nullable()();
  TextColumn get priority => textEnum<TaskPriority>()();
  TextColumn get status => textEnum<TaskStatus>()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  DateTimeColumn get remindAt => dateTime().nullable()();
  TextColumn get labels =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get recurrence =>
      text().nullable().map(const RecurrenceConverter())();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  TextColumn get goalId => text().nullable()();
  TextColumn get calendarEventId => text().nullable()();
  IntColumn get estimateMinutes => integer().nullable()();
  TextColumn get aiReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('CalendarEventRow')
class CalendarEvents extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  // Named `startsAt`/`endsAt` rather than `start`/`end`: `END` is a SQL
  // keyword and quoting it everywhere is more trouble than a clearer name.
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get kind => textEnum<EventKind>()();
  TextColumn get location => text().withDefault(const Constant(''))();
  TextColumn get recurrence =>
      text().nullable().map(const RecurrenceConverter())();
  TextColumn get reminderOffsets =>
      text().map(const IntListConverter()).withDefault(const Constant('[10]'))();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFF06A6C1))();
  TextColumn get peopleIds =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get taskId => text().nullable()();
  BoolColumn get isAiScheduled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('MoneyCategoryRow')
class MoneyCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get emoji => text().withDefault(const Constant('💸'))();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFF12B886))();
  TextColumn get kind => textEnum<TransactionType>()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('TransactionRow')
class MoneyTransactions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get occurredAt => dateTime()();
  IntColumn get amountMinor => integer()();
  TextColumn get type => textEnum<TransactionType>()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get categoryId => text().nullable()();
  TextColumn get merchant => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get tags =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get recurrence =>
      text().nullable().map(const RecurrenceConverter())();
  TextColumn get receiptPath => text().nullable()();
  TextColumn get receiptText => text().nullable()();
  TextColumn get savingsGoalId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('BudgetRow')
class Budgets extends Table {
  TextColumn get id => text()();
  IntColumn get limitMinor => integer()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get monthKey => text().nullable()();
  BoolColumn get rollsOver => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('SavingsGoalRow')
class SavingsGoals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get targetMinor => integer()();
  IntColumn get savedMinor => integer().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get emoji => text().withDefault(const Constant('🎯'))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get achievedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('HealthMetricRow')
class HealthMetrics extends Table {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<HealthKind>()();
  RealColumn get value => real()();
  DateTimeColumn get recordedAt => dateTime()();
  TextColumn get dayKey => text().withLength(min: 10, max: 10)();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get source => text().withDefault(const Constant('manual'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('HealthTargetRow')
class HealthTargets extends Table {
  TextColumn get kind => textEnum<HealthKind>()();
  RealColumn get target => real()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{kind};
}

@DataClassName('PersonRow')
class People extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get relation => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get details =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  DateTimeColumn get birthday => dateTime().nullable()();
  TextColumn get avatarPath => text().nullable()();
  IntColumn get followUpEveryDays => integer().nullable()();
  DateTimeColumn get lastInteractionAt => dateTime().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('InteractionRow')
class Interactions extends Table {
  TextColumn get id => text()();
  TextColumn get personId =>
      text().references(People, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get channel => textEnum<InteractionChannel>()();
  TextColumn get summary => text().withDefault(const Constant(''))();
  TextColumn get journalEntryId => text().nullable()();
  TextColumn get eventId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('ChatThreadRow')
class ChatThreads extends Table {
  TextColumn get id => text()();
  TextColumn get title =>
      text().withDefault(const Constant('New conversation'))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('ChatMessageRow')
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get threadId =>
      text().references(ChatThreads, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => textEnum<ChatRole>()();
  TextColumn get content => text()();
  TextColumn get citations => text()
      .map(const CitationListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get model => text().nullable()();
  TextColumn get error => text().nullable()();
  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('InsightRow')
class Insights extends Table {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<InsightKind>()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get citations => text()
      .map(const CitationListConverter())
      .withDefault(const Constant('[]'))();
  RealColumn get confidence => real().withDefault(const Constant(0.7))();
  DateTimeColumn get periodStart => dateTime().nullable()();
  DateTimeColumn get periodEnd => dateTime().nullable()();
  TextColumn get data =>
      text().map(const JsonMapConverter()).withDefault(const Constant('{}'))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get dismissed => boolean().withDefault(const Constant(false))();
  TextColumn get model => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('ReviewRow')
class PeriodReviews extends Table {
  TextColumn get id => text()();
  TextColumn get period => textEnum<ReviewPeriod>()();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();
  TextColumn get headline => text().withDefault(const Constant(''))();
  TextColumn get narrative => text().withDefault(const Constant(''))();
  TextColumn get wins =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get attentionAreas =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get recommendations =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get metrics => text()
      .map(const DoubleMapConverter())
      .withDefault(const Constant('{}'))();
  TextColumn get citations => text()
      .map(const CitationListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get model => text().nullable()();
  DateTimeColumn get generatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
        <Column<Object>>{period, periodStart},
      ];
}

@DataClassName('LifeScoreRow')
class LifeScores extends Table {
  TextColumn get dayKey => text().withLength(min: 10, max: 10)();
  IntColumn get habits => integer()();
  IntColumn get health => integer()();
  IntColumn get finances => integer()();
  IntColumn get productivity => integer()();
  IntColumn get mood => integer()();
  TextColumn get missingPillars =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  DateTimeColumn get computedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dayKey};
}

/// Denormalised search index.
///
/// Every module writes a row here on save, which turns cross-module search into
/// a single scan instead of a nine-way union. Swapping this for SQLite FTS5 is
/// a drop-in change behind `SearchRepository` — see docs/DATABASE_SCHEMA.md.
@DataClassName('SearchDocRow')
class SearchDocs extends Table {
  TextColumn get id => text()();
  TextColumn get source => textEnum<CitationSource>()();
  TextColumn get sourceId => text()();
  TextColumn get title => text()();

  /// Lower-cased haystack; the display text lives on the source record.
  TextColumn get body => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get imagePath => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('RecentQueryRow')
class RecentQueries extends Table {
  TextColumn get query => text()();
  DateTimeColumn get searchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{query};
}

/// Outbox for offline-first sync.
///
/// Writes land in the local database first and enqueue an operation here; the
/// sync service drains the queue whenever the device is online. Nothing in the
/// UI ever waits on the network.
@DataClassName('SyncOpRow')
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();

  /// `upsert` or `delete`.
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}
