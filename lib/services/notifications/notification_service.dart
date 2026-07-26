import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/utils/app_logger.dart';

/// Notification channels, one per kind of nudge, so the user can silence
/// "drink water" without losing "your meeting starts in 10 minutes".
enum ReminderChannel {
  briefing('briefing', 'Daily briefing', Importance.defaultImportance),
  reflection('reflection', 'Evening reflection', Importance.defaultImportance),
  habit('habit', 'Habit reminders', Importance.defaultImportance),
  task('task', 'Task reminders', Importance.high),
  event('event', 'Calendar events', Importance.high),
  health('health', 'Health nudges', Importance.low),
  money('money', 'Spending and bills', Importance.defaultImportance),
  people('people', 'Stay in touch', Importance.low);

  const ReminderChannel(this.id, this.label, this.importance);

  final String id;
  final String label;
  final Importance importance;
}

class NotificationService {
  NotificationService(this._ref);

  final Ref _ref;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;

  /// Deep link emitted when the user taps a notification; the router listens.
  final StreamController<String> _taps = StreamController<String>.broadcast();

  Stream<String> get onTap => _taps.stream;

  Future<void> initialize() async {
    if (_initialised) return;
    _initialised = true;

    tz_data.initializeTimeZones();

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Permission is requested later, in context, rather than on first
          // launch — users say yes far more often when they know what for.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _taps.add(payload);
      },
    );

    await _createChannels();
    await _initPush();
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    for (final channel in ReminderChannel.values) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          channel.id,
          channel.label,
          importance: channel.importance,
        ),
      );
    }
  }

  /// Firebase is optional. Without `google-services.json` / `Info.plist` entries
  /// this fails, and that must not be fatal — every reminder LifeOS actually
  /// needs is scheduled locally.
  Future<void> _initPush() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final token = await FirebaseMessaging.instance.getToken();
      AppLogger.info('push', 'FCM token acquired: ${token != null}');

      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        unawaited(
          showNow(
            title: notification.title ?? 'LifeOS',
            body: notification.body ?? '',
            channel: ReminderChannel.briefing,
            payload: message.data['route'] as String?,
          ),
        );
      });
    } catch (error) {
      AppLogger.info('push', 'Firebase not configured — local only ($error)');
    }
  }

  Future<Result<bool>> requestPermission() => Result.guard(() async {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (android != null) {
          return await android.requestNotificationsPermission() ?? false;
        }
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }, onError: (e, s) => const PermissionFailure(
            'Notifications were not allowed.',
            permission: 'notifications',
          ));

  NotificationDetails _details(ReminderChannel channel) => NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.label,
          importance: channel.importance,
          priority: Priority.defaultPriority,
          styleInformation: const BigTextStyleInformation(''),
        ),
        iOS: const DarwinNotificationDetails(),
      );

  Future<void> showNow({
    required String title,
    required String body,
    required ReminderChannel channel,
    String? payload,
  }) =>
      _plugin.show(
        _idFor('now-${DateTime.now().microsecondsSinceEpoch}'),
        title,
        body,
        _details(channel),
        payload: payload,
      );

  /// Schedules a one-off reminder.
  ///
  /// Returns without scheduling when the time has already passed — silently
  /// dropping stale reminders is better than firing a burst of them after a
  /// device has been off.
  Future<Result<void>> schedule({
    required String key,
    required String title,
    required String body,
    required DateTime when,
    required ReminderChannel channel,
    String? payload,
  }) =>
      Result.guard(() async {
        if (!_ref.read(settingsProvider).notificationsEnabled) return;
        if (when.isBefore(DateTime.now())) return;

        await _plugin.zonedSchedule(
          _idFor(key),
          title,
          body,
          tz.TZDateTime.from(when, tz.local),
          _details(channel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      }, onError: (e, s) => UnknownFailure(cause: e));

  /// Repeats daily at [time].
  Future<Result<void>> scheduleDaily({
    required String key,
    required String title,
    required String body,
    required TimeOfDay time,
    required ReminderChannel channel,
    String? payload,
  }) =>
      Result.guard(() async {
        if (!_ref.read(settingsProvider).notificationsEnabled) return;

        final now = tz.TZDateTime.now(tz.local);
        var next = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        );
        if (!next.isAfter(now)) next = next.add(const Duration(days: 1));

        await _plugin.zonedSchedule(
          _idFor(key),
          title,
          body,
          next,
          _details(channel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
      }, onError: (e, s) => UnknownFailure(cause: e));

  Future<void> cancel(String key) => _plugin.cancel(_idFor(key));

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();

  /// Stable 31-bit id from a string key, so rescheduling the same logical
  /// reminder replaces it instead of stacking duplicates.
  int _idFor(String key) => key.hashCode & 0x7fffffff;

  void dispose() => unawaited(_taps.close());
}

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>((ref) {
  final service = NotificationService(ref);
  ref.onDispose(service.dispose);
  return service;
});
