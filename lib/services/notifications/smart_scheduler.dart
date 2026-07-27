import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/result.dart';
import '../../core/extensions/date_time_x.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/mood_entry.dart';
import '../../domain/entities/person.dart';
import '../../domain/entities/task.dart';
import 'notification_service.dart';

/// Decides *when* a reminder should fire, not just that it should.
///
/// The naive version fires every habit at its configured time and buries the
/// user at 09:00. This spreads reminders out, skips anything already done, and
/// — when smart timing is on — moves nudges towards the hours the user has
/// historically been receptive, inferred from when they actually log things.
class SmartScheduler {
  const SmartScheduler(this._ref);

  final Ref _ref;

  NotificationService get _notifications =>
      _ref.read(notificationServiceProvider);

  /// Rebuilds the whole schedule. Cheap enough to run on every app resume,
  /// which is also the only way to stay correct after a timezone change.
  Future<Result<int>> rescheduleAll() => Result.guard(() async {
        final settings = _ref.read(settingsProvider);
        if (!settings.notificationsEnabled) {
          await _notifications.cancelAll();
          return 0;
        }

        var scheduled = 0;
        scheduled += await _scheduleDailyRituals();
        scheduled += await _scheduleHabits();
        scheduled += await _scheduleTasks();
        scheduled += await _scheduleEvents();
        scheduled += await _scheduleFollowUps();
        return scheduled;
      });

  Future<int> _scheduleDailyRituals() async {
    final settings = _ref.read(settingsProvider);

    await _notifications.scheduleDaily(
      key: 'briefing',
      title: 'Your day ahead',
      body: 'Here is what matters today.',
      time: settings.dailyBriefingTime,
      channel: ReminderChannel.briefing,
      payload: '/home',
    );
    await _notifications.scheduleDaily(
      key: 'reflection',
      title: 'Two minutes to reflect',
      body: 'How did today actually go?',
      time: settings.eveningReflectionTime,
      channel: ReminderChannel.reflection,
      payload: '/journal/compose',
    );
    return 2;
  }

  Future<int> _scheduleHabits() async {
    final habits = await _ref.read(habitRepositoryProvider).watchHabits().first;
    final preferred = await _preferredHour();
    var count = 0;
    var offsetMinutes = 0;

    for (final habit in habits) {
      if (habit.reminderMinutes == null) continue;

      final settings = _ref.read(settingsProvider);
      final base = settings.smartReminderTiming && preferred != null
          ? TimeOfDay(hour: preferred, minute: 0)
          : TimeOfDay(
              hour: habit.reminderMinutes! ~/ 60,
              minute: habit.reminderMinutes! % 60,
            );

      // Stagger by 7 minutes so five habits do not arrive as one wall of
      // notifications.
      final staggered = _addMinutes(base, offsetMinutes);
      offsetMinutes += 7;

      await _notifications.scheduleDaily(
        key: 'habit-${habit.id}',
        title: '${habit.emoji} ${habit.name}',
        body: habit.kind.name == 'quantity'
            ? 'Target: ${habit.target} ${habit.unit}'
            : 'Still time today.',
        time: staggered,
        channel: ReminderChannel.habit,
        payload: '/habits',
      );
      count++;
    }
    return count;
  }

  Future<int> _scheduleTasks() async {
    final tasks = await _ref.read(taskRepositoryProvider).all();
    var count = 0;

    for (final task in (tasks.valueOrNull ?? const <Task>[]).take(40)) {
      final remindAt = task.remindAt ??
          // No explicit reminder? Nudge an hour before it is due, which is
          // still actionable, unlike a notification at the deadline itself.
          (task.dueAt == null
              ? null
              : task.dueAt!.subtract(const Duration(hours: 1)));
      if (remindAt == null || remindAt.isBefore(DateTime.now())) continue;

      await _notifications.schedule(
        key: 'task-${task.id}',
        title: task.title,
        body: task.dueAt == null
            ? 'Reminder'
            : 'Due ${Fmt.time(task.dueAt!)}',
        when: remindAt,
        channel: ReminderChannel.task,
        payload: '/tasks',
      );
      count++;
    }
    return count;
  }

  Future<int> _scheduleEvents() async {
    final now = DateTime.now();
    final events = await _ref
        .read(calendarRepositoryProvider)
        .range(now, now.add(const Duration(days: 14)));

    var count = 0;
    for (final event in (events.valueOrNull ?? const <CalendarEvent>[]).take(60)) {
      for (final offset in event.reminderOffsets) {
        final when = event.start.subtract(Duration(minutes: offset));
        if (when.isBefore(now)) continue;
        await _notifications.schedule(
          key: 'event-${event.id}-$offset',
          title: event.title,
          body: offset == 0
              ? 'Starting now'
              : 'In $offset minutes'
                  '${event.location.isEmpty ? '' : ' · ${event.location}'}',
          when: when,
          channel: ReminderChannel.event,
          payload: '/calendar',
        );
        count++;
      }
    }
    return count;
  }

  Future<int> _scheduleFollowUps() async {
    final people = await _ref.read(peopleRepositoryProvider).needingFollowUp();
    var count = 0;

    for (final person in (people.valueOrNull ?? const <Person>[]).take(5)) {
      final days = person.daysSinceContact;
      await _notifications.schedule(
        key: 'person-${person.id}',
        title: 'Check in with ${person.name}',
        body: days == null
            ? 'You have not logged a conversation yet.'
            : 'It has been $days days.',
        // Late afternoon: people answer messages then, not at 07:00.
        when: DateTime.now().addDays(1).withTime(17, 30),
        channel: ReminderChannel.people,
        payload: '/people',
      );
      count++;
    }
    return count;
  }

  /// The hour of day the user most often logs something.
  ///
  /// A behavioural signal beats a configured one: if every mood check-in lands
  /// at 21:00, that is when they are actually looking at the app.
  Future<int?> _preferredHour() async {
    final now = DateTime.now();
    final moods = await _ref
        .read(moodRepositoryProvider)
        .range(now.subtract(const Duration(days: 60)), now);
    final entries = moods.valueOrNull ?? const <MoodEntry>[];
    if (entries.length < 10) return null;

    final histogram = <int, int>{};
    for (final entry in entries) {
      histogram[entry.recordedAt.hour] =
          (histogram[entry.recordedAt.hour] ?? 0) + 1;
    }
    final ranked = histogram.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final hour = ranked.first.key;

    // Never schedule into the night, whatever the data says.
    return hour < 7 || hour > 22 ? null : hour;
  }

  TimeOfDay _addMinutes(TimeOfDay time, int minutes) {
    final total = (time.hour * 60 + time.minute + minutes) % (24 * 60);
    return TimeOfDay(hour: total ~/ 60, minute: total % 60);
  }
}

final Provider<SmartScheduler> smartSchedulerProvider =
    Provider<SmartScheduler>(SmartScheduler.new);
