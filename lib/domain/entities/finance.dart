import 'package:freezed_annotation/freezed_annotation.dart';

import 'recurrence.dart';

part 'finance.freezed.dart';
part 'finance.g.dart';

enum TransactionType { income, expense, transfer }

/// Money is stored as integer minor units (cents) throughout LifeOS. Doubles
/// are never used for amounts — they lose the last cent under summation, and
/// budgets are exactly where that shows up.
@freezed
abstract class MoneyCategory with _$MoneyCategory {
  const factory MoneyCategory({
    required String id,
    required String name,
    @Default('💸') String emoji,
    @Default(0xFF12B886) int colorValue,
    @Default(TransactionType.expense) TransactionType kind,
    @Default(false) bool isSystem,
  }) = _MoneyCategory;

  factory MoneyCategory.fromJson(Map<String, dynamic> json) =>
      _$MoneyCategoryFromJson(json);
}

@freezed
abstract class MoneyTransaction with _$MoneyTransaction {
  const factory MoneyTransaction({
    required String id,
    required DateTime occurredAt,
    required int amountMinor,
    required TransactionType type,
    required DateTime createdAt,
    @Default('USD') String currency,
    String? categoryId,
    @Default('') String merchant,
    @Default('') String note,
    @Default(<String>[]) List<String> tags,
    Recurrence? recurrence,

    /// Path to a scanned receipt image, if any.
    String? receiptPath,

    /// Raw OCR text, kept so search can find "that lunch with the client".
    String? receiptText,
    String? savingsGoalId,
    DateTime? deletedAt,
  }) = _MoneyTransaction;

  const MoneyTransaction._();

  factory MoneyTransaction.fromJson(Map<String, dynamic> json) =>
      _$MoneyTransactionFromJson(json);

  /// Signed value: expenses are negative so a period can be summed directly.
  int get signedMinor => switch (type) {
        TransactionType.income => amountMinor,
        TransactionType.expense => -amountMinor,
        TransactionType.transfer => 0,
      };

  bool get isRecurring => recurrence != null;
}

@freezed
abstract class Budget with _$Budget {
  const factory Budget({
    required String id,
    required int limitMinor,
    required DateTime createdAt,

    /// Null means "everything" — a total monthly budget.
    String? categoryId,
    @Default('USD') String currency,

    /// `yyyy-MM`, or null for a budget that rolls forward every month.
    String? monthKey,
    @Default(true) bool rollsOver,
  }) = _Budget;

  factory Budget.fromJson(Map<String, dynamic> json) => _$BudgetFromJson(json);
}

/// A budget with its spending filled in — what the UI actually renders.
@freezed
abstract class BudgetProgress with _$BudgetProgress {
  const factory BudgetProgress({
    required Budget budget,
    required int spentMinor,
    required int daysRemaining,
  }) = _BudgetProgress;

  const BudgetProgress._();

  factory BudgetProgress.fromJson(Map<String, dynamic> json) =>
      _$BudgetProgressFromJson(json);

  double get fraction =>
      budget.limitMinor == 0 ? 0 : spentMinor / budget.limitMinor;

  int get remainingMinor => budget.limitMinor - spentMinor;

  bool get isOver => spentMinor > budget.limitMinor;

  /// Straight-line projection to the end of the period.
  int get projectedMinor {
    if (daysRemaining <= 0) return spentMinor;
    final elapsed = 30 - daysRemaining;
    if (elapsed <= 0) return spentMinor;
    return (spentMinor / elapsed * 30).round();
  }
}

@freezed
abstract class SavingsGoal with _$SavingsGoal {
  const factory SavingsGoal({
    required String id,
    required String name,
    required int targetMinor,
    required DateTime createdAt,
    @Default(0) int savedMinor,
    @Default('USD') String currency,
    @Default('🎯') String emoji,
    DateTime? dueDate,
    DateTime? achievedAt,
  }) = _SavingsGoal;

  const SavingsGoal._();

  factory SavingsGoal.fromJson(Map<String, dynamic> json) =>
      _$SavingsGoalFromJson(json);

  double get progress =>
      targetMinor == 0 ? 0 : (savedMinor / targetMinor).clamp(0.0, 1.0);
}

/// A recurring charge the app detected rather than one the user declared.
@freezed
abstract class DetectedSubscription with _$DetectedSubscription {
  const factory DetectedSubscription({
    required String merchant,
    required int amountMinor,
    required int intervalDays,
    required DateTime lastChargedAt,
    @Default('USD') String currency,
    @Default(<String>[]) List<String> transactionIds,

    /// 0–1: how regular the interval and amount have been.
    @Default(0) double confidence,
  }) = _DetectedSubscription;

  const DetectedSubscription._();

  factory DetectedSubscription.fromJson(Map<String, dynamic> json) =>
      _$DetectedSubscriptionFromJson(json);

  DateTime get nextChargeEstimate =>
      lastChargedAt.add(Duration(days: intervalDays));

  int get annualCostMinor => (amountMinor * 365 / intervalDays).round();
}

/// Result of `AIService.analyzeExpenses`.
@freezed
abstract class ExpenseAnalysis with _$ExpenseAnalysis {
  const factory ExpenseAnalysis({
    required DateTime periodStart,
    required DateTime periodEnd,
    required int totalSpentMinor,
    required int totalIncomeMinor,
    @Default('USD') String currency,
    @Default(<String, int>{}) Map<String, int> byCategory,
    @Default(<String>[]) List<String> habits,
    @Default(<String>[]) List<String> savingsSuggestions,
    @Default(<DetectedSubscription>[]) List<DetectedSubscription> subscriptions,
    int? projectedNextMonthMinor,
    String? summary,
  }) = _ExpenseAnalysis;

  const ExpenseAnalysis._();

  factory ExpenseAnalysis.fromJson(Map<String, dynamic> json) =>
      _$ExpenseAnalysisFromJson(json);

  int get netMinor => totalIncomeMinor - totalSpentMinor;

  double get savingsRate =>
      totalIncomeMinor == 0 ? 0 : netMinor / totalIncomeMinor;
}
