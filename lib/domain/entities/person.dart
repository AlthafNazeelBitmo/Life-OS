import 'package:freezed_annotation/freezed_annotation.dart';

part 'person.freezed.dart';
part 'person.g.dart';

enum InteractionChannel { inPerson, call, message, email, video, other }

/// Someone the user wants to stay close to.
///
/// The relationship tracker is deliberately private: everything here is local
/// notes the user wrote, not a contacts sync.
@freezed
abstract class Person with _$Person {
  const factory Person({
    required String id,
    required String name,
    required DateTime createdAt,
    @Default('') String relation,
    @Default('') String notes,

    /// Facts worth remembering — allergies, kids' names, what they're working
    /// on. Surfaced before a meeting.
    @Default(<String>[]) List<String> details,
    DateTime? birthday,
    String? avatarPath,

    /// Nudge when this many days pass with no contact. Null disables it.
    int? followUpEveryDays,
    DateTime? lastInteractionAt,
    @Default(false) bool isFavorite,
  }) = _Person;

  const Person._();

  factory Person.fromJson(Map<String, dynamic> json) => _$PersonFromJson(json);

  int? get daysSinceContact => lastInteractionAt == null
      ? null
      : DateTime.now().difference(lastInteractionAt!).inDays;

  /// True when the follow-up window has elapsed.
  bool get needsFollowUp {
    final every = followUpEveryDays;
    if (every == null) return false;
    final since = daysSinceContact;
    return since == null || since >= every;
  }

  /// Next birthday as an upcoming date, ignoring the birth year.
  DateTime? get nextBirthday {
    final date = birthday;
    if (date == null) return null;
    final now = DateTime.now();
    final thisYear = DateTime(now.year, date.month, date.day);
    return thisYear.isBefore(DateTime(now.year, now.month, now.day))
        ? DateTime(now.year + 1, date.month, date.day)
        : thisYear;
  }
}

@freezed
abstract class Interaction with _$Interaction {
  const factory Interaction({
    required String id,
    required String personId,
    required DateTime occurredAt,
    @Default(InteractionChannel.inPerson) InteractionChannel channel,
    @Default('') String summary,
    String? journalEntryId,
    String? eventId,
  }) = _Interaction;

  factory Interaction.fromJson(Map<String, dynamic> json) =>
      _$InteractionFromJson(json);
}
