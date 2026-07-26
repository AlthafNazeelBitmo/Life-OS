import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../domain/entities/chat.dart' show CitationSource;
import '../../domain/entities/person.dart';
import '../../domain/repositories/people_repository.dart';
import '../local/app_database.dart';
import '../local/search_indexer.dart';
import '../mappers/mappers.dart';
import '../remote/sync_queue_writer.dart';

class PeopleRepositoryImpl implements PeopleRepository {
  PeopleRepositoryImpl(this._db, this._sync) : _indexer = SearchIndexer(_db);

  final AppDatabase _db;
  final SyncQueueWriter _sync;
  final SearchIndexer _indexer;

  @override
  Stream<List<Person>> watchPeople() => (_db.select(_db.people)
        ..orderBy(<OrderClauseGenerator<$PeopleTable>>[
          (t) => OrderingTerm.desc(t.isFavorite),
          (t) => OrderingTerm.asc(t.name),
        ]))
      .watch()
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<Person?> watchPerson(String id) =>
      (_db.select(_db.people)..where((t) => t.id.equals(id)))
          .watchSingleOrNull()
          .map((row) => row?.toEntity());

  @override
  Stream<List<Interaction>> watchInteractions(String personId) =>
      (_db.select(_db.interactions)
            ..where((t) => t.personId.equals(personId))
            ..orderBy(<OrderClauseGenerator<$InteractionsTable>>[
              (t) => OrderingTerm.desc(t.occurredAt),
            ]))
          .watch()
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<Person>> upsert(Person person) => Result.guard(() async {
        await _db.transaction(() async {
          await _db.into(_db.people).insertOnConflictUpdate(person.toCompanion());
          await _indexer.index(
            source: CitationSource.person,
            sourceId: person.id,
            title: person.name,
            body: <String>[
              person.relation,
              person.notes,
              ...person.details,
            ].join(' '),
            occurredAt: person.lastInteractionAt ?? person.createdAt,
            imagePath: person.avatarPath,
          );
          await _sync.enqueue(
            entity: 'people',
            entityId: person.id,
            operation: SyncOperation.upsert,
            payload: person.toJson(),
          );
        });
        return person;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> delete(String id) => Result.guard(() async {
        await _db.transaction(() async {
          await (_db.delete(_db.people)..where((t) => t.id.equals(id))).go();
          await _indexer.remove(CitationSource.person, id);
          await _sync.enqueue(
            entity: 'people',
            entityId: id,
            operation: SyncOperation.delete,
            payload: const <String, dynamic>{},
          );
        });
      });

  @override
  Future<Result<Interaction>> logInteraction(Interaction interaction) =>
      Result.guard(() async {
        await _db.transaction(() async {
          await _db
              .into(_db.interactions)
              .insertOnConflictUpdate(interaction.toCompanion());
          // Denormalised onto the person so the follow-up query stays a single
          // indexed scan rather than a join over every interaction.
          await (_db.update(_db.people)
                ..where((t) => t.id.equals(interaction.personId)))
              .write(
            PeopleCompanion(lastInteractionAt: Value(interaction.occurredAt)),
          );
        });
        return interaction;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<List<Person>>> needingFollowUp() => Result.guard(() async {
        final rows = await (_db.select(_db.people)
              ..where((t) => t.followUpEveryDays.isNotNull()))
            .get();
        final people = rows.map((r) => r.toEntity()).where((p) => p.needsFollowUp).toList()
          ..sort((a, b) {
            final aDays = a.daysSinceContact ?? 9999;
            final bDays = b.daysSinceContact ?? 9999;
            return bDays.compareTo(aDays);
          });
        return people;
      });

  @override
  Future<Result<List<Person>>> birthdaysWithin(int days) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.people)
              ..where((t) => t.birthday.isNotNull()))
            .get();
        final now = DateTime.now();
        final people = rows
            .map((r) => r.toEntity())
            .where((person) {
              final next = person.nextBirthday;
              return next != null && next.difference(now).inDays <= days;
            })
            .toList()
          ..sort((a, b) => a.nextBirthday!.compareTo(b.nextBirthday!));
        return people;
      });

  @override
  Future<Result<List<Person>>> matchNames(List<String> names) =>
      Result.guard(() async {
        if (names.isEmpty) return const <Person>[];
        final rows = await _db.select(_db.people).get();
        final wanted = names.map((n) => n.toLowerCase().trim()).toSet();

        return rows
            .map((r) => r.toEntity())
            .where((person) {
              final full = person.name.toLowerCase();
              final first = full.split(' ').first;
              // Matching is exact on the full name or the first name — fuzzy
              // matching here would silently attach the wrong person to a
              // journal entry, which is worse than missing the link.
              return wanted.contains(full) || wanted.contains(first);
            })
            .toList();
      });
}
