import 'package:drift/drift.dart';

import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/extensions/date_time_x.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/chat.dart' show CitationSource;
import '../../domain/entities/finance.dart';
import '../../domain/repositories/finance_repository.dart';
import '../local/app_database.dart';
import '../local/search_indexer.dart';
import '../mappers/mappers.dart';
import '../remote/sync_queue_writer.dart';

class FinanceRepositoryImpl implements FinanceRepository {
  FinanceRepositoryImpl(this._db, this._sync) : _indexer = SearchIndexer(_db);

  final AppDatabase _db;
  final SyncQueueWriter _sync;
  final SearchIndexer _indexer;

  @override
  Stream<List<MoneyTransaction>> watchTransactions({
    DateTime? from,
    DateTime? to,
    String? categoryId,
    int limit = 100,
  }) {
    final query = _db.select(_db.moneyTransactions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<$MoneyTransactionsTable>>[
        (t) => OrderingTerm.desc(t.occurredAt),
      ])
      ..limit(limit);
    if (from != null) {
      query.where((t) => t.occurredAt.isBiggerOrEqualValue(from));
    }
    if (to != null) query.where((t) => t.occurredAt.isSmallerOrEqualValue(to));
    if (categoryId != null) query.where((t) => t.categoryId.equals(categoryId));
    return query.watch().map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<MoneyCategory>> watchCategories() =>
      (_db.select(_db.moneyCategories)
            ..orderBy(<OrderClauseGenerator<$MoneyCategoriesTable>>[
              (t) => OrderingTerm.asc(t.name),
            ]))
          .watch()
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<BudgetProgress>> watchBudgets(DateTime month) {
    final monthKey = Fmt.monthKey(month);
    final start = month.startOfMonth;
    final end = month.endOfMonth;

    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
            _db.budgets,
            _db.moneyTransactions,
          },
        )
        .watch()
        .asyncMap((_) async {
          final budgets = await (_db.select(_db.budgets)
                ..where((t) => t.monthKey.equals(monthKey) | t.monthKey.isNull()))
              .get();
          final spend = await spendByCategory(start, end);
          final byCategory = spend.valueOrNull ?? const <String, int>{};
          final total = byCategory.values.fold<int>(0, (sum, v) => sum + v);
          final daysLeft = end.difference(DateTime.now()).inDays.clamp(0, 31);

          return budgets
              .map((row) => row.toEntity())
              .map(
                (budget) => BudgetProgress(
                  budget: budget,
                  spentMinor: budget.categoryId == null
                      ? total
                      : byCategory[budget.categoryId] ?? 0,
                  daysRemaining: daysLeft,
                ),
              )
              .toList();
        });
  }

  @override
  Stream<List<SavingsGoal>> watchSavingsGoals() =>
      _db.select(_db.savingsGoals).watch().map(
            (rows) => rows.map((r) => r.toEntity()).toList(),
          );

  @override
  Future<Result<List<MoneyTransaction>>> range(DateTime from, DateTime to) =>
      Result.guard(() async {
        final rows = await (_db.select(_db.moneyTransactions)
              ..where((t) =>
                  t.occurredAt.isBetweenValues(from, to) & t.deletedAt.isNull())
              ..orderBy(<OrderClauseGenerator<$MoneyTransactionsTable>>[
                (t) => OrderingTerm.desc(t.occurredAt),
              ]))
            .get();
        return rows.map((r) => r.toEntity()).toList();
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<MoneyTransaction>> upsert(MoneyTransaction transaction) =>
      Result.guard(() async {
        await _db.transaction(() async {
          await _db
              .into(_db.moneyTransactions)
              .insertOnConflictUpdate(transaction.toCompanion());
          await _indexer.index(
            source: CitationSource.transaction,
            sourceId: transaction.id,
            title: transaction.merchant.isEmpty
                ? Fmt.money(
                    transaction.amountMinor,
                    currency: transaction.currency,
                  )
                : transaction.merchant,
            body: <String>[
              transaction.note,
              transaction.receiptText ?? '',
              ...transaction.tags,
            ].join(' '),
            occurredAt: transaction.occurredAt,
          );
          await _sync.enqueue(
            entity: 'money_transactions',
            entityId: transaction.id,
            operation: SyncOperation.upsert,
            payload: transaction.toJson(),
          );
        });
        return transaction;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<void>> delete(String id) => Result.guard(() async {
        await _db.transaction(() async {
          await (_db.update(_db.moneyTransactions)..where((t) => t.id.equals(id)))
              .write(
            MoneyTransactionsCompanion(deletedAt: Value(DateTime.now())),
          );
          await _indexer.remove(CitationSource.transaction, id);
          await _sync.enqueue(
            entity: 'money_transactions',
            entityId: id,
            operation: SyncOperation.delete,
            payload: const <String, dynamic>{},
          );
        });
      });

  @override
  Future<Result<MoneyCategory>> upsertCategory(MoneyCategory category) =>
      Result.guard(() async {
        await _db
            .into(_db.moneyCategories)
            .insertOnConflictUpdate(category.toCompanion());
        return category;
      });

  @override
  Future<Result<Budget>> upsertBudget(Budget budget) => Result.guard(() async {
        await _db.into(_db.budgets).insertOnConflictUpdate(budget.toCompanion());
        return budget;
      });

  @override
  Future<Result<void>> deleteBudget(String id) => Result.guard(() async {
        await (_db.delete(_db.budgets)..where((t) => t.id.equals(id))).go();
      });

  @override
  Future<Result<SavingsGoal>> upsertSavingsGoal(SavingsGoal goal) =>
      Result.guard(() async {
        await _db
            .into(_db.savingsGoals)
            .insertOnConflictUpdate(goal.toCompanion());
        return goal;
      });

  @override
  Future<Result<void>> contributeToSavings(String goalId, int amountMinor) =>
      Result.guard(() async {
        await _db.transaction(() async {
          // Incremented in SQL so two quick taps cannot lose a contribution.
          await _db.customStatement(
            'UPDATE savings_goals SET saved_minor = saved_minor + ? '
            'WHERE id = ?',
            <Object?>[amountMinor, goalId],
          );
          final row = await (_db.select(_db.savingsGoals)
                ..where((t) => t.id.equals(goalId)))
              .getSingleOrNull();
          if (row != null &&
              row.savedMinor >= row.targetMinor &&
              row.achievedAt == null) {
            await (_db.update(_db.savingsGoals)
                  ..where((t) => t.id.equals(goalId)))
                .write(SavingsGoalsCompanion(achievedAt: Value(DateTime.now())));
          }
        });
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<int>> spentOn(DateTime day) => Result.guard(() async {
        final row = await _db.customSelect(
          'SELECT COALESCE(SUM(amount_minor), 0) AS total '
          'FROM money_transactions '
          "WHERE type = 'expense' AND deleted_at IS NULL "
          'AND occurred_at BETWEEN ? AND ?',
          variables: <Variable<Object>>[
            Variable.withDateTime(day.startOfDay),
            Variable.withDateTime(day.endOfDay),
          ],
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
            _db.moneyTransactions,
          },
        ).getSingle();
        return row.read<int>('total');
      });

  @override
  Future<Result<Map<String, int>>> spendByCategory(
    DateTime from,
    DateTime to,
  ) =>
      Result.guard(() async {
        final rows = await _db.customSelect(
          'SELECT COALESCE(category_id, ?) AS cid, '
          'SUM(amount_minor) AS total FROM money_transactions '
          "WHERE type = 'expense' AND deleted_at IS NULL "
          'AND occurred_at BETWEEN ? AND ? GROUP BY cid',
          variables: <Variable<Object>>[
            const Variable<String>('uncategorised'),
            Variable.withDateTime(from),
            Variable.withDateTime(to),
          ],
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
            _db.moneyTransactions,
          },
        ).get();

        return <String, int>{
          for (final row in rows) row.read<String>('cid'): row.read<int>('total'),
        };
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<Map<String, int>>> dailyTotals(DateTime from, DateTime to) =>
      Result.guard(() async {
        final transactions = await (_db.select(_db.moneyTransactions)
              ..where((t) =>
                  t.occurredAt.isBetweenValues(from, to) & t.deletedAt.isNull()))
            .get();

        final totals = <String, int>{};
        for (final row in transactions) {
          final key = Fmt.dayKey(row.occurredAt);
          totals[key] = (totals[key] ?? 0) + row.toEntity().signedMinor;
        }
        return totals;
      });

  @override
  Future<Result<List<DetectedSubscription>>> detectSubscriptions({
    int lookbackDays = 180,
  }) =>
      Result.guard(() async {
        final since =
            DateTime.now().subtract(Duration(days: lookbackDays)).startOfDay;
        final rows = await (_db.select(_db.moneyTransactions)
              ..where((t) =>
                  t.occurredAt.isBiggerOrEqualValue(since) &
                  t.deletedAt.isNull() &
                  t.type.equalsValue(TransactionType.expense) &
                  t.merchant.equals('').not())
              ..orderBy(<OrderClauseGenerator<$MoneyTransactionsTable>>[
                (t) => OrderingTerm.asc(t.occurredAt),
              ]))
            .get();

        final byMerchant = <String, List<TransactionRow>>{};
        for (final row in rows) {
          byMerchant
              .putIfAbsent(row.merchant.toLowerCase().trim(), () => <TransactionRow>[])
              .add(row);
        }

        final detected = <DetectedSubscription>[];
        for (final entry in byMerchant.entries) {
          final charges = entry.value;
          if (charges.length < 3) continue;

          // A subscription looks like: same merchant, near-identical amount, at
          // a near-constant interval. All three have to hold — a favourite
          // coffee shop matches the first two and must not be flagged.
          final amounts =
              charges.map((c) => c.amountMinor).toList(growable: false);
          final median = (List<int>.from(amounts)..sort())[amounts.length ~/ 2];
          if (median == 0) continue;
          final amountSpread = amounts
              .map((a) => (a - median).abs() / median)
              .reduce((a, b) => a > b ? a : b);
          if (amountSpread > 0.15) continue;

          final gaps = <int>[
            for (var i = 1; i < charges.length; i++)
              charges[i].occurredAt.difference(charges[i - 1].occurredAt).inDays,
          ];
          if (gaps.isEmpty) continue;
          final avgGap = gaps.reduce((a, b) => a + b) / gaps.length;
          if (avgGap < 6 || avgGap > 400) continue;

          final gapSpread = gaps
              .map((g) => (g - avgGap).abs() / avgGap)
              .reduce((a, b) => a > b ? a : b);
          if (gapSpread > 0.25) continue;

          detected.add(
            DetectedSubscription(
              merchant: charges.last.merchant,
              amountMinor: median,
              intervalDays: avgGap.round(),
              lastChargedAt: charges.last.occurredAt,
              currency: charges.last.currency,
              transactionIds: charges.map((c) => c.id).toList(),
              confidence:
                  (1 - ((amountSpread + gapSpread) / 2)).clamp(0.0, 1.0),
            ),
          );
        }

        detected.sort(
          (a, b) => b.annualCostMinor.compareTo(a.annualCostMinor),
        );
        return detected;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));

  @override
  Future<Result<int>> materialiseRecurring(DateTime month) =>
      Result.guard(() async {
        final templates = await (_db.select(_db.moneyTransactions)
              ..where((t) => t.recurrence.isNotNull() & t.deletedAt.isNull()))
            .get();

        var created = 0;
        final start = month.startOfMonth;
        final end = month.endOfMonth;

        await _db.transaction(() async {
          for (final row in templates) {
            final template = row.toEntity();
            final rule = template.recurrence!;
            for (final day in daysInRange(start, end)) {
              if (!rule.occursOn(day, anchor: template.occurredAt)) continue;
              if (!day.isAfter(template.occurredAt)) continue;

              // Deterministic id keeps a second run from double-billing.
              final id = stableId('recurring', '${template.id}:${Fmt.dayKey(day)}');
              final exists = await (_db.select(_db.moneyTransactions)
                    ..where((t) => t.id.equals(id)))
                  .getSingleOrNull();
              if (exists != null) continue;

              await _db.into(_db.moneyTransactions).insert(
                    template
                        .copyWith(
                          id: id,
                          occurredAt: day,
                          createdAt: DateTime.now(),
                          recurrence: null,
                        )
                        .toCompanion(),
                  );
              created++;
            }
          }
        });
        return created;
      }, onError: (e, s) => DatabaseFailure(cause: e, stackTrace: s));
}
