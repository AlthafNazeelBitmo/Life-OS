import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/extensions/date_time_x.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/timeline_item.dart';
import '../../domain/repositories/timeline_repository.dart';
import '../local/app_database.dart';
import '../mappers/mappers.dart';

/// Builds the unified timeline by projecting each module's rows into
/// [TimelineItem]s.
///
/// Every source is queried with the same `before`/`limit` window and then
/// merged and re-trimmed, so one very chatty module (expenses, typically)
/// cannot crowd everything else out of a page.
class TimelineRepositoryImpl implements TimelineRepository {
  const TimelineRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<Result<List<TimelineItem>>> page({
    required DateTime before,
    int limit = 40,
    Set<TimelineKind> kinds = const <TimelineKind>{},
    String? query,
  }) =>
      Result.guard(() async {
        bool wanted(TimelineKind kind) => kinds.isEmpty || kinds.contains(kind);
        final items = <TimelineItem>[];

        if (wanted(TimelineKind.journal) || wanted(TimelineKind.photo)) {
          items.addAll(await _journalItems(before, limit));
        }
        if (wanted(TimelineKind.expense)) {
          items.addAll(await _expenseItems(before, limit));
        }
        if (wanted(TimelineKind.event) || wanted(TimelineKind.meeting)) {
          items.addAll(await _eventItems(before, limit));
        }
        if (wanted(TimelineKind.milestone) || wanted(TimelineKind.goal)) {
          items.addAll(await _goalItems(before, limit));
        }
        if (wanted(TimelineKind.task)) {
          items.addAll(await _taskItems(before, limit));
        }
        if (wanted(TimelineKind.mood)) {
          items.addAll(await _moodItems(before, limit));
        }

        var merged = items
            .where((item) => item.occurredAt.isBefore(before))
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

        if (query != null && query.trim().isNotEmpty) {
          final needle = query.toLowerCase().trim();
          merged = merged
              .where((item) => item.searchableText.toLowerCase().contains(needle))
              .toList();
        }
        return merged.take(limit).toList();
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<List<TimelineItem>>> forDay(DateTime day) async {
    final result = await page(before: day.endOfDay, limit: 200);
    return result.map(
      (items) => items.where((item) => item.occurredAt.isSameDay(day)).toList(),
    );
  }

  @override
  Future<Result<List<Memory>>> memoriesFor(DateTime day) =>
      Result.guard(() async {
        final suffix = '-${day.month.toString().padLeft(2, '0')}'
            '-${day.day.toString().padLeft(2, '0')}';
        final rows = await (_db.select(_db.journalEntries)
              ..where((t) =>
                  t.dayKey.like('%$suffix') &
                  t.deletedAt.isNull() &
                  t.dayKey.like('${day.year}%').not()))
            .get();

        final attachments = await (_db.select(_db.attachments)
              ..where((t) => t.entryId.isIn(rows.map((r) => r.id).toList())))
            .get();

        return rows.map((row) {
          final entry = row.toEntity();
          final photo = attachments
              .where((a) =>
                  a.entryId == row.id && a.kind == AttachmentKind.photo)
              .map((a) => a.localPath)
              .firstOrNull;
          return Memory(
            id: 'memory-${row.id}',
            originalDate: entry.createdAt,
            yearsAgo: day.year - entry.createdAt.year,
            item: TimelineItem(
              id: 'journal-${entry.id}',
              kind: TimelineKind.memory,
              occurredAt: entry.createdAt,
              title: entry.displayTitle,
              subtitle: entry.analysis?.summary ?? '',
              sourceId: entry.id,
              imagePath: photo,
              placeName: entry.location?.name,
              tags: entry.tags,
              colorValue: AppColors.journal.toARGB32(),
              significance: 0.9,
            ),
          );
        }).toList();
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<List<TimelineItem>>> places({int limit = 100}) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.journalEntries)
              ..where((t) => t.location.isNotNull() & t.deletedAt.isNull())
              ..orderBy(<OrderClauseGenerator<$JournalEntriesTable>>[
                (t) => OrderingTerm.desc(t.createdAt),
              ])
              ..limit(limit))
            .get();

        return rows.map((row) {
          final entry = row.toEntity();
          return TimelineItem(
            id: 'place-${entry.id}',
            kind: TimelineKind.trip,
            occurredAt: entry.createdAt,
            title: entry.location?.name ?? 'Unnamed place',
            subtitle: entry.displayTitle,
            sourceId: entry.id,
            placeName: entry.location?.name,
            colorValue: AppColors.journal.toARGB32(),
            significance: 0.75,
          );
        }).toList();
      });

  @override
  Future<Result<List<TimelineItem>>> highlights({
    required DateTime from,
    required DateTime to,
    int limit = 12,
  }) async {
    final result = await page(before: to, limit: 400);
    return result.map(
      (items) => (items
              .where((item) =>
                  item.occurredAt.isAfter(from) && item.isHighlight)
              .toList()
            ..sort((a, b) => b.significance.compareTo(a.significance)))
          .take(limit)
          .toList(),
    );
  }

  Future<List<TimelineItem>> _journalItems(DateTime before, int limit) async {
    final rows = await (_db.select(_db.journalEntries)
          ..where((t) =>
              t.createdAt.isSmallerThanValue(before) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<$JournalEntriesTable>>[
            (t) => OrderingTerm.desc(t.createdAt),
          ])
          ..limit(limit))
        .get();

    final attachments = await (_db.select(_db.attachments)
          ..where((t) => t.entryId.isIn(rows.map((r) => r.id).toList())))
        .get();

    return rows.map((row) {
      final entry = row.toEntity();
      final photo = attachments
          .where((a) => a.entryId == row.id && a.kind == AttachmentKind.photo)
          .map((a) => a.localPath)
          .firstOrNull;
      return TimelineItem(
        id: 'journal-${entry.id}',
        kind: photo != null ? TimelineKind.photo : TimelineKind.journal,
        occurredAt: entry.createdAt,
        title: entry.displayTitle,
        subtitle: entry.analysis?.summary ??
            (entry.body.length > 120
                ? '${entry.body.substring(0, 117)}…'
                : entry.body),
        sourceId: entry.id,
        imagePath: photo,
        placeName: entry.location?.name,
        tags: entry.tags,
        peopleIds: entry.peopleIds,
        colorValue: AppColors.journal.toARGB32(),
        // Longer, media-rich or favourited entries are the ones worth
        // resurfacing months later.
        significance: <double>[
          if (entry.isFavorite) 1.0,
          if (photo != null) 0.8,
          if (entry.wordCount > 200) 0.75,
          0.5,
        ].reduce((a, b) => a > b ? a : b),
      );
    }).toList();
  }

  Future<List<TimelineItem>> _expenseItems(DateTime before, int limit) async {
    final rows = await (_db.select(_db.moneyTransactions)
          ..where((t) =>
              t.occurredAt.isSmallerThanValue(before) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<$MoneyTransactionsTable>>[
            (t) => OrderingTerm.desc(t.occurredAt),
          ])
          ..limit(limit))
        .get();

    return rows.map((row) {
      final txn = row.toEntity();
      return TimelineItem(
        id: 'txn-${txn.id}',
        kind: TimelineKind.expense,
        occurredAt: txn.occurredAt,
        title: txn.merchant.isEmpty ? 'Transaction' : txn.merchant,
        subtitle: Fmt.money(txn.amountMinor, currency: txn.currency),
        sourceId: txn.id,
        tags: txn.tags,
        colorValue: AppColors.finance.toARGB32(),
        // Only unusually large amounts are worth a highlight slot.
        significance: txn.amountMinor >= 20000 ? 0.7 : 0.25,
      );
    }).toList();
  }

  Future<List<TimelineItem>> _eventItems(DateTime before, int limit) async {
    final rows = await (_db.select(_db.calendarEvents)
          ..where((t) =>
              t.startsAt.isSmallerThanValue(before) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<$CalendarEventsTable>>[
            (t) => OrderingTerm.desc(t.startsAt),
          ])
          ..limit(limit))
        .get();

    return rows.map((row) {
      final event = row.toEntity();
      return TimelineItem(
        id: 'event-${event.id}',
        kind: event.peopleIds.isEmpty
            ? TimelineKind.event
            : TimelineKind.meeting,
        occurredAt: event.start,
        title: event.title,
        subtitle: event.location,
        sourceId: event.id,
        peopleIds: event.peopleIds,
        placeName: event.location.isEmpty ? null : event.location,
        colorValue: event.colorValue,
        significance: 0.55,
      );
    }).toList();
  }

  Future<List<TimelineItem>> _goalItems(DateTime before, int limit) async {
    final milestones = await (_db.select(_db.milestones)
          ..where((t) => t.completedAt.isSmallerThanValue(before))
          ..orderBy(<OrderClauseGenerator<$MilestonesTable>>[
            (t) => OrderingTerm.desc(t.completedAt),
          ])
          ..limit(limit))
        .get();

    final goals = await (_db.select(_db.goals)
          ..where((t) => t.achievedAt.isSmallerThanValue(before))
          ..limit(limit))
        .get();

    return <TimelineItem>[
      for (final milestone in milestones)
        TimelineItem(
          id: 'milestone-${milestone.id}',
          kind: TimelineKind.milestone,
          occurredAt: milestone.completedAt!,
          title: milestone.title,
          subtitle: 'Milestone reached',
          sourceId: milestone.goalId,
          colorValue: AppColors.goals.toARGB32(),
          significance: 0.8,
        ),
      for (final goal in goals)
        TimelineItem(
          id: 'goal-${goal.id}',
          kind: TimelineKind.achievement,
          occurredAt: goal.achievedAt!,
          title: goal.title,
          subtitle: 'Goal achieved',
          sourceId: goal.id,
          colorValue: goal.colorValue,
          significance: 1,
        ),
    ];
  }

  Future<List<TimelineItem>> _taskItems(DateTime before, int limit) async {
    final rows = await (_db.select(_db.tasks)
          ..where((t) => t.completedAt.isSmallerThanValue(before))
          ..orderBy(<OrderClauseGenerator<$TasksTable>>[
            (t) => OrderingTerm.desc(t.completedAt),
          ])
          ..limit(limit))
        .get();

    return rows
        .map(
          (row) => TimelineItem(
            id: 'task-${row.id}',
            kind: TimelineKind.task,
            occurredAt: row.completedAt!,
            title: row.title,
            subtitle: 'Completed',
            sourceId: row.id,
            colorValue: AppColors.tasks.toARGB32(),
            significance: 0.3,
          ),
        )
        .toList();
  }

  Future<List<TimelineItem>> _moodItems(DateTime before, int limit) async {
    final rows = await (_db.select(_db.moodEntries)
          ..where((t) => t.recordedAt.isSmallerThanValue(before))
          ..orderBy(<OrderClauseGenerator<$MoodEntriesTable>>[
            (t) => OrderingTerm.desc(t.recordedAt),
          ])
          ..limit(limit))
        .get();

    return rows.map((row) {
      final mood = row.toEntity();
      return TimelineItem(
        id: 'mood-${mood.id}',
        kind: TimelineKind.mood,
        occurredAt: mood.recordedAt,
        title: '${mood.emoji} ${mood.label}',
        subtitle: mood.note ?? '',
        sourceId: mood.id,
        tags: mood.tags,
        colorValue: AppColors.mood.toARGB32(),
        // Flag only the extremes; an average day is not a highlight.
        significance: (mood.overall - 0.5).abs() > 0.3 ? 0.7 : 0.2,
      );
    }).toList();
  }
}
