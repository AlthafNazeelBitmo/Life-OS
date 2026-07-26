import '../../core/error/result.dart';
import '../entities/finance.dart';

abstract interface class FinanceRepository {
  Stream<List<MoneyTransaction>> watchTransactions({
    DateTime? from,
    DateTime? to,
    String? categoryId,
    int limit = 100,
  });

  Stream<List<MoneyCategory>> watchCategories();

  Stream<List<BudgetProgress>> watchBudgets(DateTime month);

  Stream<List<SavingsGoal>> watchSavingsGoals();

  Future<Result<List<MoneyTransaction>>> range(DateTime from, DateTime to);

  Future<Result<MoneyTransaction>> upsert(MoneyTransaction transaction);

  Future<Result<void>> delete(String id);

  Future<Result<MoneyCategory>> upsertCategory(MoneyCategory category);

  Future<Result<Budget>> upsertBudget(Budget budget);

  Future<Result<void>> deleteBudget(String id);

  Future<Result<SavingsGoal>> upsertSavingsGoal(SavingsGoal goal);

  Future<Result<void>> contributeToSavings(String goalId, int amountMinor);

  /// Net total for the day, used on the dashboard.
  Future<Result<int>> spentOn(DateTime day);

  Future<Result<Map<String, int>>> spendByCategory(
    DateTime from,
    DateTime to,
  );

  /// Daily totals for the trend chart, keyed by `yyyy-MM-dd`.
  Future<Result<Map<String, int>>> dailyTotals(DateTime from, DateTime to);

  /// Finds repeating merchant/amount pairs. Runs entirely on-device — no model
  /// call — so it works offline and never sends transactions anywhere.
  Future<Result<List<DetectedSubscription>>> detectSubscriptions({
    int lookbackDays = 180,
  });

  /// Materialises this month's occurrences of recurring bills.
  Future<Result<int>> materialiseRecurring(DateTime month);
}
