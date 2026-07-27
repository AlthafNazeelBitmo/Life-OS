import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/utils/formatters.dart';
import 'package:lifeos/data/local/app_database.dart';
import 'package:lifeos/data/remote/sync_queue_writer.dart';
import 'package:lifeos/data/repositories/journal_repository_impl.dart';
import 'package:lifeos/domain/entities/journal_entry.dart';

/// Repository tests run against a real in-memory SQLite database rather than a
/// mock: the interesting behaviour here (streak arithmetic, soft deletes, the
/// search index staying in step) lives in the SQL, and a mocked database would
/// verify nothing about it.
void main() {
  late AppDatabase db;
  late JournalRepositoryImpl repository;

  JournalEntry entryOn(DateTime date, {String body = 'A day', String? id}) {
    return JournalEntry(
      id: id ?? 'entry-${date.millisecondsSinceEpoch}',
      createdAt: date,
      updatedAt: date,
      dayKey: Fmt.dayKey(date),
      body: body,
    );
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = JournalRepositoryImpl(db, SyncQueueWriter(db));
  });

  tearDown(() async => db.close());

  test('upsert stores an entry and reads it back', () async {
    final entry = entryOn(DateTime(2026, 7, 20), body: 'Went for a long walk');

    final saved = await repository.upsert(entry);
    expect(saved.isOk, isTrue);

    final found = await repository.findById(entry.id);
    expect(found.valueOrNull?.body, 'Went for a long walk');
  });

  test('upsert replaces attachments rather than duplicating them', () async {
    final entry = entryOn(DateTime(2026, 7, 20)).copyWith(
      attachments: <Attachment>[
        Attachment(
          id: 'att-1',
          entryId: 'entry-1',
          kind: AttachmentKind.photo,
          localPath: '/tmp/a.jpg',
          createdAt: DateTime(2026, 7, 20),
        ),
      ],
    );
    final withId = entry.copyWith(id: 'entry-1');

    await repository.upsert(withId);
    await repository.upsert(withId);

    final found = await repository.findById('entry-1');
    expect(found.valueOrNull!.attachments, hasLength(1));
  });

  test('delete is soft and hides the entry from listings', () async {
    final entry = entryOn(DateTime(2026, 7, 20), id: 'soft-1');
    await repository.upsert(entry);

    await repository.delete('soft-1');

    final page = await repository.page(limit: 10, offset: 0);
    expect(page.valueOrNull, isEmpty);

    // The row survives so the deletion can be synced to other devices.
    final raw = await db.select(db.journalEntries).get();
    expect(raw, hasLength(1));
    expect(raw.single.deletedAt, isNotNull);
  });

  test('restore brings a soft-deleted entry back', () async {
    await repository.upsert(entryOn(DateTime(2026, 7, 20), id: 'r-1'));
    await repository.delete('r-1');
    await repository.restore('r-1');

    final page = await repository.page(limit: 10, offset: 0);
    expect(page.valueOrNull, hasLength(1));
  });

  group('currentStreak', () {
    test('counts consecutive days ending today', () async {
      final today = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await repository.upsert(
          entryOn(today.subtract(Duration(days: i)), id: 'streak-$i'),
        );
      }

      final streak = await repository.currentStreak();
      expect(streak.valueOrNull, 3);
    });

    test('stays alive when today has not been written yet', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await repository.upsert(entryOn(yesterday, id: 'y-1'));
      await repository.upsert(
        entryOn(
          DateTime.now().subtract(const Duration(days: 2)),
          id: 'y-2',
        ),
      );

      expect((await repository.currentStreak()).valueOrNull, 2);
    });

    test('breaks on a missed day', () async {
      final today = DateTime.now();
      await repository.upsert(entryOn(today, id: 'g-0'));
      await repository.upsert(
        entryOn(today.subtract(const Duration(days: 2)), id: 'g-2'),
      );

      expect((await repository.currentStreak()).valueOrNull, 1);
    });

    test('is zero with no entries', () async {
      expect((await repository.currentStreak()).valueOrNull, 0);
    });
  });

  test('page filters by search text', () async {
    await repository.upsert(
      entryOn(DateTime(2026, 7, 20), body: 'Ramen in Tokyo', id: 'a'),
    );
    await repository.upsert(
      entryOn(DateTime(2026, 7, 21), body: 'Quiet day at home', id: 'b'),
    );

    final hits = await repository.page(limit: 10, offset: 0, query: 'tokyo');
    expect(hits.valueOrNull, hasLength(1));
    expect(hits.valueOrNull!.single.id, 'a');
  });

  test('page paginates deterministically, newest first', () async {
    for (var i = 0; i < 5; i++) {
      await repository.upsert(
        entryOn(DateTime(2026, 7, 20 + i), id: 'p-$i'),
      );
    }

    final first = await repository.page(limit: 2, offset: 0);
    final second = await repository.page(limit: 2, offset: 2);

    expect(first.valueOrNull!.map((e) => e.id), <String>['p-4', 'p-3']);
    expect(second.valueOrNull!.map((e) => e.id), <String>['p-2', 'p-1']);
  });

  test('writes a search document alongside the entry', () async {
    await repository.upsert(
      entryOn(DateTime(2026, 7, 20), body: 'Ramen in Tokyo', id: 'idx-1'),
    );

    final docs = await db.select(db.searchDocs).get();
    expect(docs, hasLength(1));
    expect(docs.single.body, contains('tokyo'));
  });

  test('deleting removes the entry from the search index', () async {
    await repository.upsert(entryOn(DateTime(2026, 7, 20), id: 'idx-2'));
    await repository.delete('idx-2');

    expect(await db.select(db.searchDocs).get(), isEmpty);
  });

  test('onThisDay returns the same date from previous years only', () async {
    await repository.upsert(entryOn(DateTime(2024, 7, 20), id: 'old-1'));
    await repository.upsert(entryOn(DateTime(2026, 7, 20), id: 'now-1'));
    await repository.upsert(entryOn(DateTime(2024, 7, 21), id: 'other'));

    final memories = await repository.onThisDay(DateTime(2026, 7, 20));

    expect(memories.valueOrNull!.map((e) => e.id), <String>['old-1']);
  });

  test('saveAnalysis attaches AI output without touching the body', () async {
    await repository.upsert(
      entryOn(DateTime(2026, 7, 20), body: 'original text', id: 'an-1'),
    );

    await repository.saveAnalysis(
      'an-1',
      const JournalAnalysis(summary: 'A short walk', emotions: <String>['calm']),
    );

    final found = await repository.findById('an-1');
    expect(found.valueOrNull!.body, 'original text');
    expect(found.valueOrNull!.analysis!.summary, 'A short walk');
  });

  test('sync queue collapses repeated writes to one pending operation', () async {
    final entry = entryOn(DateTime(2026, 7, 20), id: 'sync-1');
    await repository.upsert(entry);
    await repository.upsert(entry.copyWith(body: 'edited'));
    await repository.upsert(entry.copyWith(body: 'edited again'));

    final queue = await db.select(db.syncQueue).get();
    expect(queue, hasLength(1));
    expect(queue.single.operation, 'upsert');
  });

  test('allTags collects the union of tags across entries', () async {
    await repository.upsert(
      entryOn(DateTime(2026, 7, 20), id: 't-1')
          .copyWith(tags: <String>['work', 'travel']),
    );
    await repository.upsert(
      entryOn(DateTime(2026, 7, 21), id: 't-2')
          .copyWith(tags: <String>['travel', 'family']),
    );

    final tags = await repository.allTags();
    expect(tags.valueOrNull, <String>['family', 'travel', 'work']);
  });
}
