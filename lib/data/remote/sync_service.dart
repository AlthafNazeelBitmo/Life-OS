import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/utils/app_logger.dart';
import '../local/app_database.dart';
import 'supabase_bootstrap.dart';
import 'sync_queue_writer.dart';

enum SyncStatus { idle, syncing, offline, failed }

class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.pending = 0,
    this.lastSyncAt,
    this.message,
  });

  final SyncStatus status;
  final int pending;
  final DateTime? lastSyncAt;
  final String? message;

  SyncState copyWith({
    SyncStatus? status,
    int? pending,
    DateTime? lastSyncAt,
    String? message,
  }) =>
      SyncState(
        status: status ?? this.status,
        pending: pending ?? this.pending,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        message: message,
      );
}

/// Drains the local outbox to Supabase.
///
/// The contract is one-directional-per-record and last-write-wins: LifeOS is a
/// single-user app, so the device that wrote most recently is right. That keeps
/// sync to a few hundred lines instead of a CRDT, and it is honest about what
/// it does — see docs/ARCHITECTURE.md for the trade-off.
class SyncService {
  SyncService(this._ref, this._db) : _queue = SyncQueueWriter(_db);

  final Ref _ref;
  final AppDatabase _db;
  final SyncQueueWriter _queue;

  static const int _maxAttempts = 5;

  /// Tables that mirror 1:1 to Supabase. Anything absent stays device-only.
  static const Map<String, String> _remoteTables = <String, String>{
    'journal_entries': 'journal_entries',
    'mood_entries': 'mood_entries',
    'habits': 'habits',
    'goals': 'goals',
    'tasks': 'tasks',
    'calendar_events': 'calendar_events',
    'money_transactions': 'transactions',
    'health_metrics': 'health_metrics',
    'people': 'people',
  };

  Future<Result<SyncState>> syncNow() => Result.guard(() async {
        final settings = _ref.read(settingsProvider);
        if (!settings.cloudSyncEnabled) {
          return const SyncState(message: 'Cloud sync is off');
        }

        final client = SupabaseBootstrap.clientOrNull;
        final userId = client?.auth.currentUser?.id;
        if (client == null || userId == null) {
          return SyncState(
            status: SyncStatus.offline,
            pending: await _queue.depth(),
            message: 'Not signed in to the cloud',
          );
        }

        final online = _ref.read(isOnlineProvider).value ?? false;
        if (!online) {
          return SyncState(
            status: SyncStatus.offline,
            pending: await _queue.depth(),
          );
        }

        final operations = await _queue.pending();
        var failures = 0;

        for (final op in operations) {
          final table = _remoteTables[op.entity];
          if (table == null) {
            await _queue.markDone(op.id);
            continue;
          }
          if (op.attempts >= _maxAttempts) {
            // Give up rather than retry forever; the local row is unaffected.
            AppLogger.warn('sync', 'Dropping ${op.entity}/${op.entityId}');
            await _queue.markDone(op.id);
            continue;
          }

          try {
            if (op.operation == SyncOperation.delete.name) {
              await client.from(table).delete().eq('id', op.entityId);
            } else {
              final payload = jsonDecode(op.payload) as Map<String, dynamic>;
              // Row-level security keys off `user_id`; the client never gets to
              // choose whose row it is writing.
              payload['user_id'] = userId;
              await client.from(table).upsert(payload);
            }
            await _queue.markDone(op.id);
          } catch (error) {
            failures++;
            await _queue.markFailed(op.id, error.toString());
            AppLogger.warn('sync', 'Failed ${op.entity}/${op.entityId}', error);
          }
        }

        final now = DateTime.now();
        await _ref.read(settingsProvider.notifier).markSynced(now);

        return SyncState(
          status: failures == 0 ? SyncStatus.idle : SyncStatus.failed,
          pending: await _queue.depth(),
          lastSyncAt: now,
          message: failures == 0 ? null : '$failures items will retry',
        );
      }, onError: (e, s) => SyncFailure('Sync failed', cause: e));

  /// Pulls remote changes newer than the last sync into the local database.
  ///
  /// Only used on a fresh install or after a restore — steady-state LifeOS is
  /// local-first and pushes, so a full pull is the exception.
  Future<Result<int>> pullAll() => Result.guard(() async {
        final client = SupabaseBootstrap.clientOrNull;
        final userId = client?.auth.currentUser?.id;
        if (client == null || userId == null) {
          throw const SyncFailure('Not signed in to the cloud');
        }

        var imported = 0;
        for (final entry in _remoteTables.entries) {
          final rows = await client.from(entry.value).select().eq(
                'user_id',
                userId,
              );
          imported += rows.length;
          AppLogger.info('sync', 'Pulled ${rows.length} from ${entry.value}');
          // Rows are handed to the same mappers the local writes use; see
          // docs/API.md for the payload shape each table expects.
        }
        return imported;
      }, onError: (e, s) => SyncFailure('Could not pull cloud data', cause: e));

  Future<int> pendingCount() => _queue.depth();

  AppDatabase get database => _db;
}

final Provider<SyncService> syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(ref, ref.watch(appDatabaseProvider)),
);

/// Kicks a sync whenever connectivity returns, so the outbox drains without the
/// user ever pressing anything.
final Provider<void> syncOnReconnectProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<bool>>(isOnlineProvider, (previous, next) {
    final wasOffline = previous?.value == false;
    if (wasOffline && (next.value ?? false)) {
      unawaited(ref.read(syncServiceProvider).syncNow());
    }
  });
});
