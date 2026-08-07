import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/cache/key_value_store.dart';
import 'package:lifeos/core/di/core_providers.dart';
import 'package:lifeos/core/security/secure_store.dart';
import 'package:lifeos/data/local/app_database.dart';
import 'package:lifeos/data/mappers/mappers.dart';
import 'package:lifeos/domain/entities/calendar_event.dart';
import 'package:lifeos/domain/entities/chat.dart';
import 'package:lifeos/domain/entities/finance.dart';
import 'package:lifeos/domain/entities/goal.dart';
import 'package:lifeos/domain/entities/habit.dart';
import 'package:lifeos/domain/entities/health_metric.dart';
import 'package:lifeos/domain/entities/insight.dart';
import 'package:lifeos/domain/entities/journal_entry.dart';
import 'package:lifeos/domain/entities/mood_entry.dart';
import 'package:lifeos/domain/entities/person.dart';
import 'package:lifeos/domain/entities/task.dart';
import 'package:lifeos/services/export/export_service.dart';
import 'package:lifeos/services/security/encryption_service.dart';

/// Export and import are only worth anything as a pair.
///
/// Each half looked correct in isolation while import silently discarded
/// everything, so these tests exercise the whole loop: write records into one
/// database, serialise, restore into a *different, empty* database, and check
/// the records came back with their enums, lists and nested objects intact.
void main() {
  // Two open databases is the point of this file, not a mistake: they have
  // separate executors and stand in for two phones.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final DateTime day = DateTime(2026, 7, 20, 9, 30);
  const String dayKey = '2026-07-20';

  late AppDatabase source;
  late AppDatabase destination;
  late ProviderContainer sourceContainer;
  late ProviderContainer destinationContainer;
  late Directory workspace;

  /// The two containers deliberately do *not* share a secure store: a restore
  /// happens on a new phone, where nothing from the old keychain exists.
  ProviderContainer containerFor(AppDatabase db) {
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        secureStoreProvider.overrideWithValue(InMemorySecureStore()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    source = AppDatabase.forTesting(NativeDatabase.memory());
    destination = AppDatabase.forTesting(NativeDatabase.memory());
    sourceContainer = containerFor(source);
    destinationContainer = containerFor(destination);
    workspace = Directory.systemTemp.createTempSync('lifeos-backup-test');
  });

  tearDown(() async {
    await source.close();
    await destination.close();
    workspace.deleteSync(recursive: true);
  });

  /// One record in every table the backup covers, each carrying the kind of
  /// value that does not survive a lazy serialiser: an enum, a list, a nested
  /// object, a soft-delete timestamp.
  Future<void> seed(AppDatabase db) async {
    await db.into(db.journalEntries).insert(
          JournalEntry(
            id: 'j1',
            createdAt: day,
            updatedAt: day,
            dayKey: dayKey,
            title: 'Ramen in Tokyo',
            body: 'Walked for hours and ate the best bowl of my life.',
            tags: const <String>['travel', 'food'],
            peopleIds: const <String>['p1'],
            location: const GeoPoint(latitude: 35.6762, longitude: 139.6503),
            weather: 'clear',
            moodScore: 9,
            isFavorite: true,
            analysis: JournalAnalysis(
              summary: 'A long walk and a good meal.',
              emotions: const <String>['calm', 'happy'],
              sentiment: 0.8,
              analysedAt: day,
              model: 'offline',
            ),
          ).toCompanion(),
        );
    await db.into(db.attachments).insert(
          Attachment(
            id: 'a1',
            entryId: 'j1',
            kind: AttachmentKind.photo,
            localPath: 'media/a1.jpg',
            createdAt: day,
            caption: 'The bowl',
          ).toCompanion(),
        );
    await db.into(db.moodEntries).insert(
          MoodEntry(
            id: 'm1',
            recordedAt: day,
            dayKey: dayKey,
            happiness: 9,
            stress: 2,
            note: 'after the walk',
            tags: const <String>['travel'],
            journalEntryId: 'j1',
          ).toCompanion(),
        );
    await db.into(db.habits).insert(
          Habit(
            id: 'h1',
            name: 'Walk 10k steps',
            createdAt: day,
            kind: HabitKind.quantity,
            cadence: HabitCadence.daily,
            target: 10000,
            unit: 'steps',
            reminderMinutes: 480,
            goalId: 'g1',
          ).toCompanion(),
        );
    await db.into(db.habitLogs).insert(
          HabitLog(
            id: 'hl1',
            habitId: 'h1',
            dayKey: dayKey,
            recordedAt: day,
            value: 12400,
            note: 'Tokyo counts double',
          ).toCompanion(),
        );
    await db.into(db.goals).insert(
          Goal(
            id: 'g1',
            title: 'Move every day',
            createdAt: day,
            horizon: GoalHorizon.longTerm,
            status: GoalStatus.active,
            targetDate: DateTime(2026, 12, 31),
            habitIds: const <String>['h1'],
          ).toCompanion(),
        );
    await db.into(db.milestones).insert(
          const Milestone(
            id: 'ms1',
            goalId: 'g1',
            title: 'Thirty days unbroken',
            position: 0,
          ).toCompanion(),
        );
    await db.into(db.tasks).insert(
          Task(
            id: 't1',
            title: 'Book the return flight',
            createdAt: day,
            status: TaskStatus.inProgress,
            priority: TaskPriority.high,
            labels: const <String>['travel'],
            dueAt: DateTime(2026, 7, 25),
            estimateMinutes: 20,
            goalId: 'g1',
          ).toCompanion(),
        );
    await db.into(db.calendarEvents).insert(
          CalendarEvent(
            id: 'e1',
            title: 'Dinner with Mika',
            start: DateTime(2026, 7, 21, 19),
            end: DateTime(2026, 7, 21, 21),
            createdAt: day,
            kind: EventKind.meeting,
            location: 'Shinjuku',
            reminderOffsets: const <int>[30, 10],
            peopleIds: const <String>['p1'],
          ).toCompanion(),
        );
    await db.into(db.moneyCategories).insert(
          const MoneyCategory(
            id: 'c1',
            name: 'Eating out',
            kind: TransactionType.expense,
          ).toCompanion(),
        );
    await db.into(db.moneyTransactions).insert(
          MoneyTransaction(
            id: 'tx1',
            occurredAt: day,
            amountMinor: 1850,
            type: TransactionType.expense,
            createdAt: day,
            currency: 'JPY',
            categoryId: 'c1',
            merchant: 'Ichiran',
            tags: const <String>['travel'],
          ).toCompanion(),
        );
    await db.into(db.budgets).insert(
          Budget(
            id: 'b1',
            limitMinor: 50000,
            createdAt: day,
            categoryId: 'c1',
            currency: 'JPY',
            monthKey: '2026-07',
          ).toCompanion(),
        );
    await db.into(db.savingsGoals).insert(
          SavingsGoal(
            id: 'sg1',
            name: 'Next trip',
            targetMinor: 400000,
            createdAt: day,
          ).toCompanion(),
        );
    await db.into(db.healthMetrics).insert(
          HealthMetric(
            id: 'hm1',
            kind: HealthKind.steps,
            value: 12400,
            recordedAt: day,
            dayKey: dayKey,
            source: 'manual',
          ).toCompanion(),
        );
    await db.into(db.people).insert(
          Person(
            id: 'p1',
            name: 'Mika',
            createdAt: day,
            relation: 'friend',
            details: const <String>['allergic to shellfish'],
            followUpEveryDays: 30,
            lastInteractionAt: day,
          ).toCompanion(),
        );
    await db.into(db.interactions).insert(
          Interaction(
            id: 'i1',
            personId: 'p1',
            occurredAt: day,
            channel: InteractionChannel.inPerson,
            summary: 'Caught up over ramen',
            journalEntryId: 'j1',
          ).toCompanion(),
        );
    await db.into(db.insights).insert(
          Insight(
            id: 'in1',
            kind: InsightKind.correlation,
            title: 'Walking lifts your mood',
            body: 'Days over 10k steps score 1.8 higher on happiness.',
            createdAt: day,
            confidence: 0.62,
            citations: const <Citation>[
              Citation(id: 'j1', source: CitationSource.journal, label: 'Jul 20'),
            ],
            data: const <String, dynamic>{'x': 'steps', 'y': 'happiness'},
          ).toCompanion(),
        );
  }

  Future<File> writeBackup(Map<String, dynamic> payload, String name) async {
    final file = File('${workspace.path}/$name');
    return file.writeAsString(jsonEncode(payload));
  }

  /// How many records a payload holds, per table. Derived rather than hardcoded
  /// because the database seeds its own system categories on first open, and a
  /// literal here would quietly stop meaning "everything" the day a table is
  /// added to the export.
  Map<String, int> countsIn(Map<String, dynamic> payload) => <String, int>{
        for (final entry in payload.entries)
          if (entry.value is List && (entry.value as List<dynamic>).isNotEmpty)
            entry.key: (entry.value as List<dynamic>).length,
      };

  test('a plain JSON backup restores every table into an empty database',
      () async {
    await seed(source);

    final payload = await sourceContainer.read(exportServiceProvider).snapshot();
    final file = await writeBackup(payload, 'backup.json');

    final result =
        await destinationContainer.read(exportServiceProvider).importJson(file);

    final summary = result.valueOrNull;
    expect(result.isOk, isTrue, reason: '${result.failureOrNull?.message}');
    expect(summary!.totalSkipped, 0, reason: 'skipped ${summary.skipped}');
    // Every table in the archive came back, with nothing dropped on the way.
    expect(summary.written, countsIn(payload));
  });

  test('restored records keep their enums, lists and nested objects', () async {
    await seed(source);
    final payload = await sourceContainer.read(exportServiceProvider).snapshot();

    await destinationContainer
        .read(exportServiceProvider)
        .importJson(await writeBackup(payload, 'backup.json'));

    final entry = (await destination.select(destination.journalEntries).get())
        .single
        .toEntity();
    expect(entry.title, 'Ramen in Tokyo');
    expect(entry.tags, <String>['travel', 'food']);
    expect(entry.location?.latitude, closeTo(35.6762, 0.0001));
    expect(entry.analysis?.emotions, <String>['calm', 'happy']);
    expect(entry.isFavorite, isTrue);

    // The nested attachment on the entry must not be written twice: it arrives
    // in its own list and the two copies share an id.
    final attachments =
        await destination.select(destination.attachments).get();
    expect(attachments, hasLength(1));
    expect(attachments.single.caption, 'The bowl');

    final task =
        (await destination.select(destination.tasks).get()).single.toEntity();
    expect(task.status, TaskStatus.inProgress);
    expect(task.priority, TaskPriority.high);
    expect(task.labels, <String>['travel']);

    final transaction =
        (await destination.select(destination.moneyTransactions).get())
            .single
            .toEntity();
    expect(transaction.type, TransactionType.expense);
    expect(transaction.amountMinor, 1850);
    expect(transaction.currency, 'JPY');

    final event = (await destination.select(destination.calendarEvents).get())
        .single
        .toEntity();
    expect(event.kind, EventKind.meeting);
    expect(event.reminderOffsets, <int>[30, 10]);

    final metric = (await destination.select(destination.healthMetrics).get())
        .single
        .toEntity();
    expect(metric.kind, HealthKind.steps);
    expect(metric.value, 12400);

    final insight =
        (await destination.select(destination.insights).get()).single.toEntity();
    expect(insight.kind, InsightKind.correlation);
    expect(insight.citations.single.source, CitationSource.journal);
    expect(insight.data['x'], 'steps');
  });

  test('restoring twice merges by id rather than duplicating', () async {
    await seed(source);
    final payload = await sourceContainer.read(exportServiceProvider).snapshot();
    final file = await writeBackup(payload, 'backup.json');

    final service = destinationContainer.read(exportServiceProvider);
    await service.importJson(file);
    final second = await service.importJson(file);

    expect(second.valueOrNull!.written, countsIn(payload));
    expect(await destination.select(destination.journalEntries).get(),
        hasLength(1));
    expect(await destination.select(destination.tasks).get(), hasLength(1));
  });

  test('restoring makes the records searchable', () async {
    await seed(source);
    final payload = await sourceContainer.read(exportServiceProvider).snapshot();

    await destinationContainer
        .read(exportServiceProvider)
        .importJson(await writeBackup(payload, 'backup.json'));

    final docs = await destination.select(destination.searchDocs).get();
    expect(docs, isNotEmpty);
    expect(
      docs.any((doc) => doc.body.contains('tokyo')),
      isTrue,
      reason: 'the imported journal entry was never indexed',
    );
  });

  test('an encrypted backup opens on a device that has never seen it',
      () async {
    await seed(source);
    const passphrase = 'correct horse battery staple';

    final payload = await sourceContainer.read(exportServiceProvider).snapshot();
    final plaintext = jsonEncode(payload);
    final envelope = await sourceContainer
        .read(encryptionServiceProvider)
        .encrypt(plaintext, passphrase: passphrase);
    expect(envelope.isOk, isTrue);

    final file = File('${workspace.path}/backup.lifeos');
    await file.writeAsString(envelope.valueOrNull!);

    // destinationContainer has its own empty secure store, which is the whole
    // point: the salt has to travel inside the file or the backup is a hostage.
    final result = await destinationContainer
        .read(exportServiceProvider)
        .importJson(file, passphrase: passphrase);

    expect(result.isOk, isTrue, reason: '${result.failureOrNull?.message}');
    expect(result.valueOrNull!.written, countsIn(payload));
  });

  test('the wrong passphrase fails cleanly instead of writing garbage',
      () async {
    await seed(source);
    final plaintext = jsonEncode(
      await sourceContainer.read(exportServiceProvider).snapshot(),
    );
    final envelope = await sourceContainer
        .read(encryptionServiceProvider)
        .encrypt(plaintext, passphrase: 'the right one');

    final file = File('${workspace.path}/backup.lifeos');
    await file.writeAsString(envelope.valueOrNull!);

    final result = await destinationContainer
        .read(exportServiceProvider)
        .importJson(file, passphrase: 'the wrong one');

    expect(result.isOk, isFalse);
    expect(await destination.select(destination.journalEntries).get(), isEmpty);
  });

  test('a file that is not a backup is rejected by name, not by crash',
      () async {
    final file = File('${workspace.path}/notes.json');
    await file.writeAsString('this is not JSON at all');

    final result =
        await destinationContainer.read(exportServiceProvider).importJson(file);

    expect(result.isOk, isFalse);
    expect(result.failureOrNull!.message, contains('not a LifeOS backup'));
  });

  test('a backup from a newer schema is refused rather than half-applied',
      () async {
    final file = await writeBackup(<String, dynamic>{
      'schema_version': 99,
      'journal_entries': <dynamic>[],
    }, 'future.json');

    final result =
        await destinationContainer.read(exportServiceProvider).importJson(file);

    expect(result.isOk, isFalse);
    expect(result.failureOrNull!.message, contains('newer version'));
  });

  test('one malformed record is skipped without abandoning the rest', () async {
    await seed(source);
    final payload = await sourceContainer.read(exportServiceProvider).snapshot();
    final intact = countsIn(payload);
    // A journal entry missing its required day key: the kind of row a
    // hand-edited or partially-written backup contains.
    (payload['journal_entries']! as List<dynamic>).add(<String, dynamic>{
      'id': 'broken',
      'createdAt': day.toIso8601String(),
    });

    final result = await destinationContainer
        .read(exportServiceProvider)
        .importJson(await writeBackup(payload, 'backup.json'));

    final summary = result.valueOrNull!;
    expect(summary.skipped, <String, int>{'journal_entries': 1});
    expect(summary.written, intact);
  });
}
