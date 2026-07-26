import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../config/env.dart';

/// Thin wrapper over `package:logging` so feature code never talks to `print`.
///
/// In release builds only warnings and above are emitted, and messages are
/// routed through `dart:developer` so they surface in DevTools/Crashlytics
/// without leaking to stdout.
abstract final class AppLogger {
  const AppLogger._();

  static bool _initialised = false;

  static void init() {
    if (_initialised) return;
    _initialised = true;
    Logger.root.level = Env.isRelease ? Level.WARNING : Level.ALL;
    Logger.root.onRecord.listen((record) {
      developer.log(
        record.message,
        time: record.time,
        level: record.level.value,
        name: record.loggerName,
        error: record.error,
        stackTrace: record.stackTrace,
      );
    });
  }

  static Logger of(String name) => Logger(name);

  static void debug(String name, String message) => Logger(name).fine(message);

  static void info(String name, String message) => Logger(name).info(message);

  static void warn(String name, String message, [Object? error]) =>
      Logger(name).warning(message, error);

  static void error(
    String name,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) =>
      Logger(name).severe(message, error, stackTrace);

  /// Installs Flutter's global error hooks. Wire your crash reporter here.
  static void installErrorHandlers() {
    FlutterError.onError = (details) {
      Logger('flutter').severe(
        details.summary.toString(),
        details.exception,
        details.stack,
      );
      if (!Env.isRelease) FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      Logger('platform').severe('Uncaught async error', error, stack);
      return true;
    };
  }
}
