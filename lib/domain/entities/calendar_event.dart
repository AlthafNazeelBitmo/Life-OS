import 'package:freezed_annotation/freezed_annotation.dart';

import 'recurrence.dart';

part 'calendar_event.freezed.dart';
part 'calendar_event.g.dart';

enum EventKind { event, meeting, birthday, deadline, reminder, travel, focus }

@freezed
abstract class CalendarEvent with _$CalendarEvent {
  const factory CalendarEvent({
    required String id,
    required String title,
    required DateTime start,
    required DateTime end,
    required DateTime createdAt,
    @Default('') String description,
    @Default(false) bool allDay,
    @Default(EventKind.event) EventKind kind,
    @Default('') String location,
    Recurrence? recurrence,

    /// Minutes before start; multiple reminders per event are allowed.
    @Default(<int>[10]) List<int> reminderOffsets,
    @Default(0xFF06A6C1) int colorValue,

    /// People attending — links meetings to the relationship tracker.
    @Default(<String>[]) List<String> peopleIds,
    String? taskId,

    /// True when the assistant created this block rather than the user.
    @Default(false) bool isAiScheduled,
    DateTime? deletedAt,
  }) = _CalendarEvent;

  const CalendarEvent._();

  factory CalendarEvent.fromJson(Map<String, dynamic> json) =>
      _$CalendarEventFromJson(json);

  Duration get duration => end.difference(start);

  bool get isPast => end.isBefore(DateTime.now());

  bool get isNow {
    final now = DateTime.now();
    return !start.isAfter(now) && end.isAfter(now);
  }

  /// Whether this event (including its repeats) lands on [day].
  bool occursOn(DateTime day) {
    final rule = recurrence;
    if (rule == null) {
      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      return start.isBefore(dayEnd) && end.isAfter(dayStart);
    }
    return rule.occursOn(day, anchor: start);
  }

  /// This event projected onto [day], preserving time of day. Used to render
  /// repeats without materialising rows for every occurrence.
  CalendarEvent occurrenceOn(DateTime day) {
    if (recurrence == null) return this;
    final shifted = DateTime(
      day.year,
      day.month,
      day.day,
      start.hour,
      start.minute,
    );
    return copyWith(start: shifted, end: shifted.add(duration));
  }
}

/// Free window found by the scheduler, offered for focus work.
@freezed
abstract class FreeSlot with _$FreeSlot {
  const factory FreeSlot({
    required DateTime start,
    required DateTime end,
  }) = _FreeSlot;

  const FreeSlot._();

  factory FreeSlot.fromJson(Map<String, dynamic> json) =>
      _$FreeSlotFromJson(json);

  Duration get duration => end.difference(start);
}
