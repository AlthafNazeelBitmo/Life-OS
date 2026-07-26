import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/local/app_database.dart';
import 'package:lifeos/data/remote/sync_queue_writer.dart';
import 'package:lifeos/data/repositories/habit_repository_impl.dart';
import 'package:lifeos/domain/entities/habit.dart';

void main() {
  late AppDatabase db;
  late HabitRepositoryImpl repository;

  final createdAt = DateTime.now().subtract(const Duration(days: 40));

  Habit daily({String id = 'h1', int target = 1, HabitKind kind = HabitKind.binary}) =>
      Habit(
        id: id,
        name: 'Meditate',
        createdAt: createdAt,
        target: target,
        kind: kind,
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = HabitRepositoryImpl(db, SyncQueueWriter(db));
  });

  tearDown(() async => db.close());

  test('logging the same day twice updates rather than duplicating', () async {
    await repository.upsert(daily());
    final today = DateTime.now();

    await repository.log('h1', today);
    await repository.log('h1', today, amount: 3);

    final logs = await db.select(db.habitLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.value, 3);
  });

  test('logging zero clears the day instead of storing a zero', () async {
    await repository.upsert(daily());
    final today = DateTime.now();

    await repository.log('h1', today);
    await repository.log('h1', today, amount: 0);

    expect(await db.select(db.habitLogs).get(), isEmpty);
  });

  group('stats', () {
    test('counts a current streak ending today', () async {
      await repository.upsert(daily());
      final today = DateTime.now();
      for (var i = 0; i < 4; i++) {
        await repository.log('h1', today.subtract(Duration(days: i)));
      }

      final stats = await repository.stats('h1');
      expect(stats.valueOrNull!.currentStreak, 4);
    });

    test('does not break the streak just because today is not done yet',
        () async {
      await repository.upsert(daily());
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await repository.log('h1', yesterday);
      await repository.log(
        'h1',
        DateTime.now().subtract(const Duration(days: 2)),
      );

      expect((await repository.stats('h1')).valueOrNull!.currentStreak, 2);
    });

    test('remembers the longest streak after it has been broken', () async {
      await repository.upsert(daily());
      final today = DateTime.now();

      // A five-day run, a gap, then a two-day run.
      for (final offset in <int>[10, 9, 8, 7, 6, 3, 2]) {
        await repository.log('h1', today.subtract(Duration(days: offset)));
      }

      final stats = (await repository.stats('h1')).valueOrNull!;
      expect(stats.longestStreak, 5);
      expect(stats.currentStreak, 0);
    });

    test('quantity habits only count a day once the target is reached',
        () async {
      await repository.upsert(
        daily(target: 8, kind: HabitKind.quantity),
      );
      final today = DateTime.now();

      await repository.log('h1', today, amount: 5);
      expect((await repository.stats('h1')).valueOrNull!.currentStreak, 0);

      await repository.log('h1', today, amount: 8);
      expect((await repository.stats('h1')).valueOrNull!.currentStreak, 1);
    });

    test('completion rate only counts days the habit was scheduled', () async {
      // A weekly habit should not look 86% incomplete just because it is not
      // a daily one.
      await repository.upsert(
        Habit(
          id: 'w1',
          name: 'Deep clean',
          createdAt: createdAt,
          cadence: HabitCadence.weekly,
        ),
      );

      final stats = (await repository.stats('w1', lookbackDays: 28)).valueOrNull!;
      expect(stats.completionRate, 0);

      // Log every scheduled occurrence in the window.
      var cursor = DateTime.now();
      var logged = 0;
      while (logged < 4) {
        if (cursor.weekday == createdAt.weekday) {
          await repository.log('w1', cursor);
          logged++;
        }
        cursor = cursor.subtract(const Duration(days: 1));
      }

      final after = (await repository.stats('w1', lookbackDays: 28)).valueOrNull!;
      expect(after.completionRate, greaterThan(0.9));
    });

    test('score stays within bounds', () async {
      await repository.upsert(daily());
      for (var i = 0; i < 30; i++) {
        await repository.log('h1', DateTime.now().subtract(Duration(days: i)));
      }

      final stats = (await repository.stats('h1')).valueOrNull!;
      expect(stats.score, inInclusiveRange(0, 100));
      expect(stats.grade, isNotEmpty);
    });
  });

  test('dayCompletion is the fraction of scheduled habits done', () async {
    await repository.upsert(daily(id: 'a'));
    await repository.upsert(daily(id: 'b'));
    await repository.log('a', DateTime.now());

    expect((await repository.dayCompletion(DateTime.now())).valueOrNull, 0.5);
  });

  test('dayCompletion is zero when nothing is scheduled', () async {
    expect((await repository.dayCompletion(DateTime.now())).valueOrNull, 0);
  });

  test('archiving hides a habit from the active list', () async {
    await repository.upsert(daily());
    await repository.archive('h1');

    final habits = await repository.watchHabits().first;
    expect(habits, isEmpty);

    final withArchived = await repository.watchHabits(includeArchived: true).first;
    expect(withArchived, hasLength(1));
  });

  test('deleting a habit removes its logs', () async {
    await repository.upsert(daily());
    await repository.log('h1', DateTime.now());

    await repository.delete('h1');

    expect(await db.select(db.habitLogs).get(), isEmpty);
  });
}
