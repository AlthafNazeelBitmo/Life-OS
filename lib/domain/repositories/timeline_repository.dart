import '../../core/error/result.dart';
import '../entities/timeline_item.dart';

abstract interface class TimelineRepository {
  /// One page of the infinite timeline, newest first.
  ///
  /// Paged rather than streamed: the timeline unions every module, so a live
  /// query would re-scan all of them on any write. Pages are cheap and the
  /// screen refreshes on pull-to-refresh or when it regains focus.
  Future<Result<List<TimelineItem>>> page({
    required DateTime before,
    int limit = 40,
    Set<TimelineKind> kinds = const <TimelineKind>{},
    String? query,
  });

  Future<Result<List<TimelineItem>>> forDay(DateTime day);

  /// "On this day" — the same calendar day in previous years.
  Future<Result<List<Memory>>> memoriesFor(DateTime day);

  /// Places the user has been, newest first, for the travel timeline.
  Future<Result<List<TimelineItem>>> places({int limit = 100});

  Future<Result<List<TimelineItem>>> highlights({
    required DateTime from,
    required DateTime to,
    int limit = 12,
  });
}
