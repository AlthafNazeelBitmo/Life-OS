import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/extensions/date_time_x.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/chat.dart' show CitationSource;
import '../../domain/entities/recurrence.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../local/app_database.dart';
import '../local/search_indexer.dart';
import '../mappers/mappers.dart';
import '../remote/sync_queue_writer.dart';

class CalendarRepositoryImpl implements CalendarRepository {
  CalendarRepositoryImpl(this._db, this._sync) : _indexer = SearchIndexer(_db);

  final AppDatabase _db;
  final SyncQueueWriter _sync;
  final SearchIndexer _indexer;

  /// Expands recurring events into concrete occurrences inside the window.
  ///
  /// Occurrences are computed on read rather than materialised as rows: a
  /// "every weekday" event would otherwise generate thousands of rows that all
  /// have to be rewritten whenever the user edits the series.
  List<CalendarEvent> _expand(
    List<CalendarEventRow> rows,
    DateTime from,
    DateTime to,
  ) {
    final result = <CalendarEvent>[];
    for (final row in rows) {
      final event = row.toEntity();
      if (event.recurrence == null) {
        if (event.start.isBefore(to) && event.end.isAfter(from)) {
          result.add(event);
        }
        continue;
      }
      for (final day in daysInRange(from, to)) {
        if (event.occursOn(day)) result.add(event.occurrenceOn(day));
      }
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  Future<List<CalendarEventRow>> _candidates(DateTime from, DateTime to) =>
      (_db.select(_db.calendarEvents)
            ..where(
              (t) =>
                  t.deletedAt.isNull() &
                  // Non-recurring events must overlap the window; recurring
                  // ones only have to have started before it ends.
                  (t.recurrence.isNotNull() |
                      (t.startsAt.isSmallerThanValue(to) &
                          t.endsAt.isBiggerThanValue(from))),
            ))
          .get();

  @override
  Stream<List<CalendarEvent>> watchRange(DateTime from, DateTime to) =>
      _db.select(_db.calendarEvents).watch().asyncMap(
            (_) async => _expand(await _candidates(from, to), from, to),
          );

  @override
  Stream<List<CalendarEvent>> watchDay(DateTime day) =>
      watchRange(day.startOfDay, day.endOfDay);

  @override
  Stream<List<CalendarEvent>> watchUpcoming({int limit = 5}) {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 30));
    return watchRange(now, horizon).map(
      (events) => events.where((e) => e.end.isAfter(now)).take(limit).toList(),
    );
  }

  @override
  Future<Result<List<CalendarEvent>>> range(DateTime from, DateTime to) =>
      Result.guard(
        () async => _expand(await _candidates(from, to), from, to),
        onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s),
      );

  @override
  Future<Result<CalendarEvent>> upsert(CalendarEvent event) =>
      Result.guard(() async {
        await _db.transaction(() async {
          await _db
              .into(_db.calendarEvents)
              .insertOnConflictUpdate(event.toCompanion());
          await _indexer.index(
            source: CitationSource.event,
            sourceId: event.id,
            title: event.title,
            body: '${event.description} ${event.location}',
            occurredAt: event.start,
          );
          await _sync.enqueue(
            entity: 'calendar_events',
            entityId: event.id,
            operation: SyncOperation.upsert,
            payload: event.toJson(),
          );
        });
        return event;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> delete(String id) => Result.guard(() async {
        await _db.transaction(() async {
          await (_db.update(_db.calendarEvents)..where((t) => t.id.equals(id)))
              .write(CalendarEventsCompanion(deletedAt: Value(DateTime.now())));
          await _indexer.remove(CitationSource.event, id);
          await _sync.enqueue(
            entity: 'calendar_events',
            entityId: id,
            operation: SyncOperation.delete,
            payload: const <String, dynamic>{},
          );
        });
      });

  @override
  Future<Result<void>> move(String id, DateTime newStart) =>
      Result.guard(() async {
        final row = await (_db.select(_db.calendarEvents)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (row == null) throw const NotFoundFailure();
        final duration = row.endsAt.difference(row.startsAt);

        await (_db.update(_db.calendarEvents)..where((t) => t.id.equals(id)))
            .write(
          CalendarEventsCompanion(
            startsAt: Value(newStart),
            endsAt: Value(newStart.add(duration)),
          ),
        );
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<List<FreeSlot>>> freeSlots(
    DateTime day, {
    int minMinutes = 30,
    int dayStartHour = 8,
    int dayEndHour = 21,
  }) =>
      Result.guard(() async {
        final windowStart = day.withTime(dayStartHour, 0);
        final windowEnd = day.withTime(dayEndHour, 0);
        final events = _expand(
          await _candidates(day.startOfDay, day.endOfDay),
          day.startOfDay,
          day.endOfDay,
        ).where((e) => !e.allDay).toList();

        final slots = <FreeSlot>[];
        var cursor = windowStart;
        for (final event in events) {
          if (event.end.isBefore(windowStart)) continue;
          if (event.start.isAfter(windowEnd)) break;
          if (event.start.difference(cursor).inMinutes >= minMinutes) {
            slots.add(FreeSlot(start: cursor, end: event.start));
          }
          if (event.end.isAfter(cursor)) cursor = event.end;
        }
        if (windowEnd.difference(cursor).inMinutes >= minMinutes) {
          slots.add(FreeSlot(start: cursor, end: windowEnd));
        }
        return slots;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> syncBirthdays() => Result.guard(() async {
        final people = await (_db.select(_db.people)
              ..where((t) => t.birthday.isNotNull()))
            .get();

        await _db.transaction(() async {
          for (final person in people) {
            final birthday = person.birthday!;
            // Deterministic id: re-running this never creates duplicates.
            final id = stableId('birthday', person.id);
            final thisYear = DateTime(
              DateTime.now().year,
              birthday.month,
              birthday.day,
              9,
            );
            await _db.into(_db.calendarEvents).insertOnConflictUpdate(
                  CalendarEventsCompanion.insert(
                    id: id,
                    title: '🎂 ${person.name}',
                    startsAt: thisYear,
                    endsAt: thisYear.add(const Duration(hours: 1)),
                    createdAt: DateTime.now(),
                    kind: EventKind.birthday,
                    allDay: const Value(true),
                    recurrence: Value(
                      const Recurrence(unit: RecurrenceUnit.year),
                    ),
                    peopleIds: Value(<String>[person.id]),
                    colorValue: const Value(0xFFEC6B9B),
                  ),
                );
          }
        });
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));
}
