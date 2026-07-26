import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/cache/key_value_store.dart';
import 'core/config/env.dart';
import 'core/di/core_providers.dart';
import 'core/utils/app_logger.dart';
import 'data/remote/supabase_bootstrap.dart';
import 'services/notifications/notification_service.dart';

/// Single entry point for every flavour.
///
/// Startup does the minimum needed to paint: open the synchronous cache, then
/// run the app. Anything slower (Supabase handshake, notification channels,
/// timezone database) is kicked off after the first frame so time-to-interactive
/// does not depend on the network.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.init();
  AppLogger.installErrorHandlers();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  final keyValueStore = await HiveKeyValueStore.open();

  runApp(
    ProviderScope(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(keyValueStore),
      ],
      child: const _Startup(child: LifeOsApp()),
    ),
  );
}

/// Runs deferred initialisation once the first frame is on screen.
class _Startup extends ConsumerStatefulWidget {
  const _Startup({required this.child});

  final Widget child;

  @override
  ConsumerState<_Startup> createState() => _StartupState();
}

class _StartupState extends ConsumerState<_Startup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmUp());
  }

  Future<void> _warmUp() async {
    if (Env.hasSupabase) {
      // Failure here is non-fatal: the app keeps working against local data
      // and sync resumes when the backend becomes reachable.
      await SupabaseBootstrap.init();
    } else {
      AppLogger.info(
        'startup',
        'Supabase not configured — running in local-only mode.',
      );
    }

    await ref.read(notificationServiceProvider).initialize();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
