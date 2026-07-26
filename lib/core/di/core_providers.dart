import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../cache/key_value_store.dart';
import '../security/secure_store.dart';

/// Composition root.
///
/// Anything with a real I/O dependency is declared here as an unimplemented
/// provider and overridden once, in `bootstrap()`. Tests override the same
/// handful of providers with fakes and get a fully wired app for free.

final Provider<KeyValueStore> keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError('keyValueStoreProvider must be overridden'),
);

final Provider<SecureStore> secureStoreProvider = Provider<SecureStore>(
  (ref) => PlatformSecureStore(),
);

final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (ref) {
    final db = AppDatabase();
    ref.onDispose(db.close);
    return db;
  },
);

/// Injectable clock. Every feature reads "now" from here so tests can freeze
/// time instead of sleeping.
final Provider<DateTime Function()> clockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

final Provider<Connectivity> connectivityProvider =
    Provider<Connectivity>((ref) => Connectivity());

/// Coarse online/offline signal used to decide whether to attempt sync or a
/// remote AI call. Offline is never an error state in LifeOS — it is the
/// default assumption.
final StreamProvider<bool> isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = ref.watch(connectivityProvider);
  bool online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
});
