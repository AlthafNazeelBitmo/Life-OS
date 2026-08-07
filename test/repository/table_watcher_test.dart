import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/utils/formatters.dart';
import 'package:lifeos/data/local/app_database.dart';
import 'package:lifeos/data/local/table_watcher.dart';
import 'package:lifeos/data/mappers/mappers.dart';
import 'package:lifeos/domain/entities/journal_entry.dart';
import 'package:lifeos/domain/entities/task.dart';

/// The reminder schedule and the home-screen widgets both hang off this class,
/// so its two promises are worth pinning down: a burst of writes produces one
/// rebuild, and writes to tables it was not asked about produce none.
void main() {
  final DateTime now = DateTime(2026, 7, 20, 9);

  late AppDatabase db;
  late int runs;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    runs = 0;
  });

  tearDown(() async => db.close());

  TableWatcher watcherOn(
    List<ResultSetImplementation<dynamic, dynamic>> tables, {
    Duration settle = const Duration(milliseconds: 40),
    Duration minimumGap = Duration.zero,
    Future<void> Function()? action,
  }) {
    final watcher = TableWatcher(
      database: db,
      tables: tables,
      debugName: 'test',
      settle: settle,
      minimumGap: minimumGap,
      action: action ??
          () async {
            runs++;
          },
    )..start();
    addTearDown(watcher.dispose);
    return watcher;
  }

  Future<void> addTask(String id) => db.into(db.tasks).insert(
        Task(id: id, title: 'Task $id', createdAt: now).toCompanion(),
      );

  Future<void> addJournalEntry(String id) => db.into(db.journalEntries).insert(
        JournalEntry(
          id: id,
          createdAt: now,
          updatedAt: now,
          dayKey: Fmt.dayKey(now),
        ).toCompanion(),
      );

  test('a burst of writes produces a single run', () async {
    watcherOn(<ResultSetImplementation<dynamic, dynamic>>[db.tasks]);

    for (var i = 0; i < 5; i++) {
      await addTask('t$i');
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(runs, 1);
  });

  test('writes to other tables are ignored', () async {
    watcherOn(<ResultSetImplementation<dynamic, dynamic>>[db.tasks]);

    await addJournalEntry('j1');
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(runs, 0);
  });

  test('a later write runs again', () async {
    watcherOn(<ResultSetImplementation<dynamic, dynamic>>[db.tasks]);

    await addTask('t1');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await addTask('t2');
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(runs, 2);
  });

  test('a run inside the minimum gap is delayed, not dropped', () async {
    watcherOn(
      <ResultSetImplementation<dynamic, dynamic>>[db.tasks],
      minimumGap: const Duration(milliseconds: 150),
    );

    await addTask('t1');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(runs, 1);

    // Well inside the gap: this must not run yet, and must not be forgotten.
    await addTask('t2');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(runs, 1);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(runs, 2);
  });

  test('a failing action does not stop later runs', () async {
    var attempts = 0;
    watcherOn(
      <ResultSetImplementation<dynamic, dynamic>>[db.tasks],
      action: () async {
        attempts++;
        if (attempts == 1) throw StateError('scheduling blew up');
        runs++;
      },
    );

    await addTask('t1');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await addTask('t2');
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(attempts, 2);
    expect(runs, 1);
  });

  test('writes made inside a transaction trigger one run on commit', () async {
    watcherOn(<ResultSetImplementation<dynamic, dynamic>>[db.tasks]);

    // This is how a restore writes, so it is the path that has to work: the
    // schedule must rebuild once the whole batch has landed.
    await db.transaction(() async {
      for (var i = 0; i < 4; i++) {
        await addTask('tx$i');
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(runs, 1);
  });

  test('disposing stops the watcher', () async {
    final watcher =
        watcherOn(<ResultSetImplementation<dynamic, dynamic>>[db.tasks])
          ..dispose();

    await addTask('t1');
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(runs, 0);
    // Disposing twice is what happens when a provider rebuilds during teardown.
    expect(watcher.dispose, returnsNormally);
  });
}
