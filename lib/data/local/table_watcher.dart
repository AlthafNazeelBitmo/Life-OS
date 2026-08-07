import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/utils/app_logger.dart';
import 'app_database.dart';

/// Runs [action] shortly after writes to [tables] stop arriving.
///
/// Reminder schedules and home-screen widgets are both *derived* from the
/// database: neither is data the user edits directly, and both go stale the
/// moment a task, habit or event changes. Deriving them from table updates
/// rather than from call sites is what stops a new write path forgetting to
/// refresh them — there is nothing to remember.
///
/// The debounce matters as much as the trigger. Ticking off five habits in a
/// row is five table updates and should still be one rebuild, and a rebuild is
/// dozens of platform-channel calls.
class TableWatcher {
  TableWatcher({
    required this.database,
    required this.tables,
    required this.action,
    required this.debugName,
    this.settle = const Duration(seconds: 2),
    this.minimumGap = const Duration(seconds: 30),
  });

  final AppDatabase database;

  /// Writes to any of these queue a run.
  final List<ResultSetImplementation<dynamic, dynamic>> tables;

  final Future<void> Function() action;

  /// Used for log lines, so a slow or failing refresh can be attributed.
  final String debugName;

  /// How long the writes have to stop before a run starts.
  final Duration settle;

  /// Floor between two runs. A run that arrives too early is delayed, never
  /// dropped: the whole point is that the derived surface ends up current.
  final Duration minimumGap;

  StreamSubscription<void>? _subscription;
  Timer? _timer;
  DateTime? _lastRun;
  bool _running = false;

  void start() {
    _subscription ??= database
        .tableUpdates(TableUpdateQuery.onAllTables(tables))
        .listen((_) => schedule());
  }

  /// Queues a run after [settle].
  ///
  /// Public because callers with their own reason to rebuild — an app resume,
  /// a finished restore — should share this debounce rather than bypass it.
  void schedule() {
    _timer?.cancel();
    _timer = Timer(settle, run);
  }

  /// Rebuilds now, unless [minimumGap] has not elapsed or a run is in flight.
  Future<void> run() async {
    _timer?.cancel();
    if (_running) return;

    final last = _lastRun;
    if (last != null) {
      final waited = DateTime.now().difference(last);
      if (waited < minimumGap) {
        _timer = Timer(minimumGap - waited, run);
        return;
      }
    }

    _running = true;
    _lastRun = DateTime.now();
    try {
      await action();
    } catch (error) {
      AppLogger.warn(debugName, 'Refresh failed', error);
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
