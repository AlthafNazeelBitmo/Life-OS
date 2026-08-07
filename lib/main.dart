import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/cache/key_value_store.dart';
import 'core/config/env.dart';
import 'core/di/core_providers.dart';
import 'core/utils/app_logger.dart';
import 'data/remote/supabase_bootstrap.dart';
import 'data/remote/sync_service.dart';
import 'services/notifications/notification_service.dart';
import 'services/notifications/reminder_sync.dart';
import 'services/widgets/home_widget_service.dart';
import 'services/widgets/home_widget_sync.dart';

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

class _StartupState extends ConsumerState<_Startup> with WidgetsBindingObserver {
  bool _warmedUp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmUp());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
    await ref.read(homeWidgetServiceProvider).initialize();

    // Reading these providers is what starts them. Each subscribes to the
    // signal it reacts to — connectivity, or writes to the tables it derives
    // from — and lives as long as the ProviderScope. Nothing reads them back,
    // and that is the point: they are wiring, not state.
    ref
      ..read(syncOnReconnectProvider)
      ..read(reminderSyncProvider)
      ..read(homeWidgetSyncProvider);

    _warmedUp = true;

    // Both are stale by definition at launch: the phone may have been off for
    // a week, and neither survives a reboot on Android.
    unawaited(ref.read(reminderSyncProvider).run());
    unawaited(ref.read(homeWidgetSyncProvider).run());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_warmedUp) return;

    switch (state) {
      case AppLifecycleState.resumed:
        // Rescheduling on resume is the only thing that keeps reminders right
        // across a timezone change or a day boundary — neither of which the
        // app is awake for.
        ref.read(reminderSyncProvider).schedule();
      case AppLifecycleState.paused:
        // Leaving the app is exactly when the home-screen widget starts being
        // the only version of this data the user can see.
        unawaited(ref.read(homeWidgetSyncProvider).run());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
