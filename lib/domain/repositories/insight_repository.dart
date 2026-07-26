import '../../core/error/result.dart';
import '../entities/insight.dart';

abstract interface class InsightRepository {
  Stream<List<Insight>> watchInsights({bool includeDismissed = false});

  Future<Result<List<Insight>>> forPeriod(DateTime start, DateTime end);

  Future<Result<void>> saveAll(List<Insight> insights);

  Future<Result<void>> setPinned(String id, {required bool pinned});

  Future<Result<void>> dismiss(String id);

  Future<Result<PeriodReview?>> findReview(ReviewPeriod period, DateTime start);

  Future<Result<void>> saveReview(PeriodReview review);

  Stream<List<PeriodReview>> watchReviews(ReviewPeriod period);

  /// Latest computed life score, plus history for the trend sparkline.
  Future<Result<LifeScore>> latestLifeScore();

  Future<Result<void>> saveLifeScore(LifeScore score);

  Future<Result<List<LifeScore>>> lifeScoreHistory({int days = 90});
}
