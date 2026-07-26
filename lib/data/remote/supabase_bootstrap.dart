import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/utils/app_logger.dart';

/// Initialises Supabase, if it is configured.
///
/// Everything here is best-effort. LifeOS treats the backend as an optional
/// replica of the local database, so a failure to reach it must never block
/// startup or hide the user's data.
abstract final class SupabaseBootstrap {
  const SupabaseBootstrap._();

  static bool _ready = false;

  static bool get isReady => _ready;

  static SupabaseClient? get clientOrNull =>
      _ready ? Supabase.instance.client : null;

  static Future<void> init() async {
    if (_ready || !Env.hasSupabase) return;
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          // Sessions persist to disk so a cold start on a plane still lands the
          // user inside their data.
          autoRefreshToken: true,
        ),
      );
      _ready = true;
      AppLogger.info('supabase', 'Initialised');
    } catch (error, stackTrace) {
      AppLogger.error(
        'supabase',
        'Initialisation failed — continuing offline',
        error,
        stackTrace,
      );
    }
  }
}
