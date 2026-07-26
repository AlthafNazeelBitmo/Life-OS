import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_x.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/settings/settings_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/ids.dart';
import '../../../../data/repositories/repository_providers.dart';
import '../../../../domain/entities/finance.dart';
import '../../../../domain/entities/task.dart';

/// Horizontal row of one-tap capture actions.
///
/// Capture has to be faster than the thought — anything that takes more than a
/// tap and a number does not get logged, and unlogged data makes every insight
/// downstream worse.
class QuickAddBar extends ConsumerWidget {
  const QuickAddBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
          children: <Widget>[
            _QuickChip(
              icon: Icons.edit_note_rounded,
              label: 'Journal',
              color: AppColors.journal,
              onTap: () => context.push(Routes.journalCompose),
            ),
            _QuickChip(
              icon: Icons.mood_rounded,
              label: 'Mood',
              color: AppColors.mood,
              onTap: () => context.push(Routes.mood),
            ),
            _QuickChip(
              icon: Icons.payments_outlined,
              label: 'Expense',
              color: AppColors.finance,
              onTap: () => _quickExpense(context, ref),
            ),
            _QuickChip(
              icon: Icons.check_circle_outline_rounded,
              label: 'Task',
              color: AppColors.tasks,
              onTap: () => _quickTask(context, ref),
            ),
            _QuickChip(
              icon: Icons.event_outlined,
              label: 'Event',
              color: AppColors.calendar,
              onTap: () => context.push(Routes.calendar),
            ),
          ],
        ),
      );

  Future<void> _quickExpense(BuildContext context, WidgetRef ref) async {
    final amount = TextEditingController();
    final merchant = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Padding(
          padding: Insets.sheet,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Quick expense', style: sheetContext.text.titleLarge),
              Gap.h16,
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '${ref.read(currencyProviderSymbol)} ',
                ),
              ),
              Gap.h12,
              TextField(
                controller: merchant,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Where?'),
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
    );

    if (saved != true) return;
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (value == null || value <= 0) {
      if (context.mounted) context.showError('Enter an amount.');
      return;
    }

    final now = DateTime.now();
    final result = await ref.read(financeRepositoryProvider).upsert(
          MoneyTransaction(
            id: newId(),
            occurredAt: now,
            amountMinor: (value * 100).round(),
            type: TransactionType.expense,
            createdAt: now,
            merchant: merchant.text.trim(),
          ),
        );
    if (!context.mounted) return;
    result.fold(
      (txn) => context.showSnack(
        'Logged ${Fmt.money(txn.amountMinor, currency: txn.currency)}',
      ),
      (failure) => context.showError(failure.message),
    );
  }

  Future<void> _quickTask(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Padding(
          padding: Insets.sheet,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('New task', style: sheetContext.text.titleLarge),
              Gap.h16,
              TextField(
                controller: title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => Navigator.of(sheetContext).pop(true),
                decoration: const InputDecoration(
                  labelText: 'What needs doing?',
                ),
              ),
              Gap.h24,
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const Text('Add to today'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true || title.text.trim().isEmpty) return;
    await ref.read(taskRepositoryProvider).upsert(
          Task(
            id: newId(),
            title: title.text.trim(),
            createdAt: DateTime.now(),
            status: TaskStatus.today,
            priority: TaskPriority.medium,
          ),
        );
    if (context.mounted) context.showSnack('Added to today');
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: Gap.sm),
        child: ActionChip(
          onPressed: onTap,
          avatar: Icon(icon, size: 18, color: color),
          label: Text(label),
          tooltip: 'Quick add: $label',
        ),
      );
}

/// Currency symbol for prefix decoration, derived from the settings code.
final Provider<String> currencyProviderSymbol = Provider<String>((ref) {
  final code = ref.watch(currencyProvider);
  return switch (code) {
    'USD' => r'$',
    'EUR' => '€',
    'GBP' => '£',
    'INR' => '₹',
    'JPY' => '¥',
    _ => code,
  };
});
