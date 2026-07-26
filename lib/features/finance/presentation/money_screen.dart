import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/finance.dart';

final StreamProvider<List<MoneyTransaction>> _transactionsProvider =
    StreamProvider<List<MoneyTransaction>>((ref) {
  final now = DateTime.now();
  return ref
      .watch(financeRepositoryProvider)
      .watchTransactions(from: now.startOfMonth, to: now.endOfMonth);
});

final StreamProvider<List<MoneyCategory>> categoriesProvider =
    StreamProvider<List<MoneyCategory>>(
  (ref) => ref.watch(financeRepositoryProvider).watchCategories(),
);

final StreamProvider<List<BudgetProgress>> _budgetsProvider =
    StreamProvider<List<BudgetProgress>>(
  (ref) => ref.watch(financeRepositoryProvider).watchBudgets(DateTime.now()),
);

final FutureProvider<ExpenseAnalysis> expenseAnalysisProvider =
    FutureProvider<ExpenseAnalysis>((ref) async {
  final now = DateTime.now();
  final from = now.startOfMonth;
  final to = now.endOfMonth;
  final repository = ref.watch(financeRepositoryProvider);

  // Totals are computed from the database and handed to the model, never asked
  // of it — see DefaultAiService.analyzeExpenses.
  final transactions = (await repository.range(from, to)).valueOrNull ?? [];
  final spent = transactions
      .where((t) => t.type == TransactionType.expense)
      .fold<int>(0, (sum, t) => sum + t.amountMinor);
  final income = transactions
      .where((t) => t.type == TransactionType.income)
      .fold<int>(0, (sum, t) => sum + t.amountMinor);
  final byCategory =
      (await repository.spendByCategory(from, to)).valueOrNull ?? {};
  final subscriptions =
      (await repository.detectSubscriptions()).valueOrNull ?? [];

  final result = await ref.watch(aiServiceProvider).analyzeExpenses(
        from: from,
        to: to,
        context: await ref
            .watch(contextBuilderProvider)
            .forRange(from: from, to: to, maxChunks: 40),
        totalSpentMinor: spent,
        totalIncomeMinor: income,
        byCategory: byCategory,
        subscriptions: subscriptions,
        currency: ref.watch(currencyProvider),
      );
  return result.fold((analysis) => analysis, (failure) => throw failure);
});

class MoneyScreen extends ConsumerWidget {
  const MoneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(_transactionsProvider).valueOrNull ?? const [];
    final budgets = ref.watch(_budgetsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final analysis = ref.watch(expenseAnalysisProvider);
    final currency = ref.watch(currencyProvider);

    final spent = transactions
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (sum, t) => sum + t.amountMinor);
    final income = transactions
        .where((t) => t.type == TransactionType.income)
        .fold<int>(0, (sum, t) => sum + t.amountMinor);

    return AppBackdrop(
      accent: AppColors.finance,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'money-fab',
          onPressed: () => _addTransaction(context, ref, categories),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add'),
        ),
        body: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar.large(
              backgroundColor: Colors.transparent,
              title: const Text('Money'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 120),
              sliver: SliverList.list(
                children: <Widget>[
                  GlassCard(
                    accent: AppColors.finance,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: StatTile(
                            label: 'Spent this month',
                            value: Fmt.money(spent, currency: currency),
                            icon: Icons.trending_down_rounded,
                            accent: AppColors.negative,
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            label: 'Income',
                            value: Fmt.money(income, currency: currency),
                            icon: Icons.trending_up_rounded,
                            accent: AppColors.positive,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Gap.h16,
                  if (transactions.isNotEmpty)
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionHeader(title: 'Where it went'),
                          SizedBox(
                            height: 180,
                            child: _CategoryChart(
                              transactions: transactions,
                              categories: categories,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (budgets.isNotEmpty) ...<Widget>[
                    Gap.h16,
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionHeader(title: 'Budgets'),
                          for (final budget in budgets)
                            _BudgetRow(
                              progress: budget,
                              currency: currency,
                              categories: categories,
                            ),
                        ],
                      ),
                    ),
                  ],
                  Gap.h16,
                  GlassCard(
                    accent: AppColors.insights,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SectionHeader(
                          title: 'What I notice',
                          trailing: IconButton(
                            tooltip: 'Refresh',
                            onPressed: () =>
                                ref.invalidate(expenseAnalysisProvider),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ),
                        analysis.when(
                          loading: () => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(Gap.lg),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (_, __) => Text(
                            'Analysis unavailable right now.',
                            style: context.text.bodySmall,
                          ),
                          data: (value) => _AnalysisBody(
                            analysis: value,
                            currency: currency,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Gap.h16,
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SectionHeader(title: 'This month'),
                        if (transactions.isEmpty)
                          Text(
                            'No transactions yet.',
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          )
                        else
                          for (final transaction in transactions.take(25))
                            _TransactionRow(
                              transaction: transaction,
                              categories: categories,
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTransaction(
    BuildContext context,
    WidgetRef ref,
    List<MoneyCategory> categories,
  ) async {
    final amount = TextEditingController();
    final merchant = TextEditingController();
    var type = TransactionType.expense;
    String? categoryId = categories.isEmpty ? null : categories.first.id;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Padding(
            padding: Insets.sheet,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SegmentedButton<TransactionType>(
                  segments: const <ButtonSegment<TransactionType>>[
                    ButtonSegment<TransactionType>(
                      value: TransactionType.expense,
                      label: Text('Expense'),
                    ),
                    ButtonSegment<TransactionType>(
                      value: TransactionType.income,
                      label: Text('Income'),
                    ),
                  ],
                  selected: <TransactionType>{type},
                  onSelectionChanged: (values) =>
                      setSheetState(() => type = values.first),
                ),
                Gap.h16,
                TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                Gap.h12,
                TextField(
                  controller: merchant,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Where / what'),
                ),
                Gap.h12,
                Wrap(
                  spacing: Gap.xs,
                  children: <Widget>[
                    for (final category in categories)
                      ChoiceChip(
                        avatar: Text(category.emoji),
                        label: Text(category.name),
                        selected: categoryId == category.id,
                        onSelected: (_) =>
                            setSheetState(() => categoryId = category.id),
                      ),
                  ],
                ),
                Gap.h24,
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (value == null || value <= 0) {
      if (context.mounted) context.showError('Enter an amount.');
      return;
    }

    final now = DateTime.now();
    await ref.read(financeRepositoryProvider).upsert(
          MoneyTransaction(
            id: newId(),
            occurredAt: now,
            amountMinor: (value * 100).round(),
            type: type,
            createdAt: now,
            categoryId: categoryId,
            merchant: merchant.text.trim(),
            currency: ref.read(currencyProvider),
          ),
        );
    ref.invalidate(expenseAnalysisProvider);
  }
}

class _CategoryChart extends StatelessWidget {
  const _CategoryChart({required this.transactions, required this.categories});

  final List<MoneyTransaction> transactions;
  final List<MoneyCategory> categories;

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final transaction in transactions) {
      if (transaction.type != TransactionType.expense) continue;
      final key = transaction.categoryId ?? 'uncategorised';
      totals[key] = (totals[key] ?? 0) + transaction.amountMinor;
    }
    if (totals.isEmpty) return const SizedBox.shrink();

    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final grand = ranked.fold<int>(0, (sum, entry) => sum + entry.value);

    MoneyCategory? categoryFor(String id) {
      for (final category in categories) {
        if (category.id == id) return category;
      }
      return null;
    }

    return Row(
      children: <Widget>[
        SizedBox(
          width: 150,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 42,
              sections: <PieChartSectionData>[
                for (var i = 0; i < ranked.length && i < 6; i++)
                  PieChartSectionData(
                    value: ranked[i].value.toDouble(),
                    // Percentages inside the slices, names in the legend: a
                    // pie with eight labels around it is unreadable on a phone.
                    title:
                        '${(ranked[i].value / grand * 100).toStringAsFixed(0)}%',
                    titleStyle: context.text.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    radius: 44,
                    color: AppColors.chartSeries[i % AppColors.chartSeries.length],
                  ),
              ],
            ),
          ),
        ),
        Gap.w16,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var i = 0; i < ranked.length && i < 6; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors
                              .chartSeries[i % AppColors.chartSeries.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      Gap.w8,
                      Expanded(
                        child: Text(
                          categoryFor(ranked[i].key)?.name ?? 'Uncategorised',
                          style: context.text.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.progress,
    required this.currency,
    required this.categories,
  });

  final BudgetProgress progress;
  final String currency;
  final List<MoneyCategory> categories;

  @override
  Widget build(BuildContext context) {
    final categoryId = progress.budget.categoryId;
    final matches =
        categories.where((category) => category.id == categoryId).toList();
    final name = categoryId == null
        ? 'Everything'
        : (matches.isEmpty ? 'Uncategorised' : matches.first.name);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(name, style: context.text.bodyMedium)),
              Text(
                '${Fmt.money(progress.spentMinor, currency: currency)} / '
                '${Fmt.money(progress.budget.limitMinor, currency: currency)}',
                style: context.text.labelSmall?.copyWith(
                  color: progress.isOver
                      ? context.colors.error
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Gap.h4,
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: progress.fraction.clamp(0.0, 1.0),
              minHeight: 6,
              color: progress.isOver
                  ? context.colors.error
                  : AppColors.finance,
              backgroundColor: context.colors.surfaceContainerHighest,
            ),
          ),
          if (progress.projectedMinor > progress.budget.limitMinor &&
              !progress.isOver)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'On track to reach '
                '${Fmt.money(progress.projectedMinor, currency: currency)} '
                'by month end.',
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnalysisBody extends StatelessWidget {
  const _AnalysisBody({required this.analysis, required this.currency});

  final ExpenseAnalysis analysis;
  final String currency;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (analysis.summary != null)
            Text(analysis.summary!, style: context.text.bodyMedium),
          if (analysis.savingsSuggestions.isNotEmpty) ...<Widget>[
            Gap.h12,
            for (final suggestion in analysis.savingsSuggestions.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.savings_outlined, size: 14),
                    Gap.w8,
                    Expanded(
                      child: Text(suggestion, style: context.text.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
          if (analysis.subscriptions.isNotEmpty) ...<Widget>[
            Gap.h12,
            Text(
              'Recurring charges found',
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            for (final subscription in analysis.subscriptions.take(4))
              Text(
                '• ${subscription.merchant} — '
                '${Fmt.money(subscription.amountMinor, currency: currency)} '
                'every ${subscription.intervalDays} days '
                '(${Fmt.money(subscription.annualCostMinor, currency: currency)}/yr)',
                style: context.text.bodySmall,
              ),
          ],
          if (analysis.projectedNextMonthMinor != null) ...<Widget>[
            Gap.h12,
            Text(
              'Projected next month: '
              '${Fmt.money(analysis.projectedNextMonthMinor!, currency: currency)}',
              style: context.text.labelMedium,
            ),
          ],
        ],
      );
}

class _TransactionRow extends ConsumerWidget {
  const _TransactionRow({required this.transaction, required this.categories});

  final MoneyTransaction transaction;
  final List<MoneyCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = categories
        .where((item) => item.id == transaction.categoryId)
        .toList();
    final isExpense = transaction.type == TransactionType.expense;

    return Dismissible(
      key: ValueKey<String>(transaction.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) =>
          ref.read(financeRepositoryProvider).delete(transaction.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Gap.lg),
        child: const Icon(Icons.delete_outline_rounded),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Text(
          category.isEmpty ? '💸' : category.first.emoji,
          style: const TextStyle(fontSize: 20),
        ),
        title: Text(
          transaction.merchant.isEmpty ? 'Transaction' : transaction.merchant,
        ),
        subtitle: Text(
          Fmt.shortDate(transaction.occurredAt),
          style: context.text.labelSmall,
        ),
        trailing: Text(
          '${isExpense ? '−' : '+'}'
          '${Fmt.money(transaction.amountMinor, currency: transaction.currency)}',
          style: context.text.labelLarge?.copyWith(
            color: isExpense ? context.colors.onSurface : AppColors.positive,
          ),
        ),
      ),
    );
  }
}
