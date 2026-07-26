import 'package:freezed_annotation/freezed_annotation.dart';

part 'timeline_item.freezed.dart';
part 'timeline_item.g.dart';

enum TimelineKind {
  journal,
  photo,
  mood,
  habit,
  goal,
  milestone,
  task,
  event,
  meeting,
  expense,
  health,
  trip,
  achievement,
  memory,
}

/// A single row in the unified life timeline.
///
/// Timeline items are projections, not a separate source of truth: the
/// repository builds them from the module tables on read. That keeps them from
/// ever disagreeing with the records they describe.
@freezed
abstract class TimelineItem with _$TimelineItem {
  const factory TimelineItem({
    required String id,
    required TimelineKind kind,
    required DateTime occurredAt,
    required String title,
    @Default('') String subtitle,

    /// Id of the underlying record, for deep-linking.
    required String sourceId,
    String? imagePath,
    String? placeName,
    @Default(<String>[]) List<String> tags,
    @Default(<String>[]) List<String> peopleIds,
    int? colorValue,

    /// Ranks what shows in the condensed "highlights" view (0–1).
    @Default(0.5) double significance,
  }) = _TimelineItem;

  const TimelineItem._();

  factory TimelineItem.fromJson(Map<String, dynamic> json) =>
      _$TimelineItemFromJson(json);

  bool get isHighlight => significance >= 0.7;

  String get searchableText =>
      <String>[title, subtitle, placeName ?? '', ...tags].join(' ');
}

/// A resurfaced moment from a previous year.
@freezed
abstract class Memory with _$Memory {
  const factory Memory({
    required String id,
    required DateTime originalDate,
    required int yearsAgo,
    required TimelineItem item,
    String? aiCaption,
  }) = _Memory;

  factory Memory.fromJson(Map<String, dynamic> json) => _$MemoryFromJson(json);
}
