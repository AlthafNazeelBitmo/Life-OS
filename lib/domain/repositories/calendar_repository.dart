import '../../core/error/result.dart';
import '../entities/calendar_event.dart';

abstract interface class CalendarRepository {
  /// Events overlapping the range, with recurring events already expanded into
  /// concrete occurrences.
  Stream<List<CalendarEvent>> watchRange(DateTime from, DateTime to);

  Stream<List<CalendarEvent>> watchDay(DateTime day);

  Stream<List<CalendarEvent>> watchUpcoming({int limit = 5});

  Future<Result<List<CalendarEvent>>> range(DateTime from, DateTime to);

  Future<Result<CalendarEvent>> upsert(CalendarEvent event);

  Future<Result<void>> delete(String id);

  /// Drag-and-drop: moves an occurrence, keeping its duration.
  Future<Result<void>> move(String id, DateTime newStart);

  /// Gaps of at least [minMinutes] on [day], within working hours.
  Future<Result<List<FreeSlot>>> freeSlots(
    DateTime day, {
    int minMinutes = 30,
    int dayStartHour = 8,
    int dayEndHour = 21,
  });

  /// Creates birthday events for everyone in the relationship tracker.
  Future<Result<void>> syncBirthdays();
}
