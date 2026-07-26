import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';

enum SyncOperation { upsert, delete }

/// Writes to the offline outbox.
///
/// Repositories call this inside the same transaction as their local write, so
/// a record and its pending sync operation are committed together — the app can
/// be killed mid-save without losing the intent to sync.
///
/// The queue is deliberately last-write-wins per entity: LifeOS is
/// single-user, and a per-row merge would add conflict machinery nobody needs.
class SyncQueueWriter {
  const SyncQueueWriter(this._db, {this.enabled = true});

  final AppDatabase _db;

  /// False in local-only mode; enqueuing becomes a no-op so no history of the
  /// user's data accumulates for a backend they never opted into.
  final bool enabled;

  Future<void> enqueue({
    required String entity,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
  }) async {
    if (!enabled) return;

    // Collapse any pending op for the same record: only the latest state
    // matters, and this keeps the queue bounded during offline bursts.
    await (_db.delete(_db.syncQueue)
          ..where((t) => t.entity.equals(entity) & t.entityId.equals(entityId)))
        .go();

    await _db.into(_db.syncQueue).insert(
          SyncQueueCompanion.insert(
            entity: entity,
            entityId: entityId,
            operation: operation.name,
            payload: jsonEncode(payload),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<List<SyncOpRow>> pending({int limit = 200}) => (_db.select(_db.syncQueue)
        ..orderBy(<OrderClauseGenerator<$SyncQueueTable>>[
          (t) => OrderingTerm.asc(t.createdAt),
        ])
        ..limit(limit))
      .get();

  Future<void> markDone(int id) =>
      (_db.delete(_db.syncQueue)..where((t) => t.id.equals(id))).go();

  /// Increments in SQL rather than read-modify-write so concurrent drains
  /// cannot lose an attempt count and retry forever.
  Future<void> markFailed(int id, String error) => _db.customStatement(
        'UPDATE sync_queue SET attempts = attempts + 1, last_error = ? '
        'WHERE id = ?',
        <Object?>[error, id],
      );

  Future<int> depth() async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM sync_queue',
      readsFrom: <ResultSetImplementation<dynamic, dynamic>>{_db.syncQueue},
    ).getSingle();
    return row.read<int>('c');
  }
}
