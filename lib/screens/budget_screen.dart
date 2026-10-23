import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  Future<void> _editBudget(BuildContext context, WidgetRef ref,
      {Budget? existing, Category? category}) async {
    final s = ref.read(stringsProvider);
    final ctrl = TextEditingController(
        text: existing == null ? '' : (existing.limitPaisa / 100).toString());
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category == null
            ? s.t('overallBudget')
            : '${s.t('budgetFor')} ${category.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              prefixText: 'Rs ', labelText: s.t('monthlyLimit')),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(context, -1.0),
              child: Text(s.t('remove')),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.t('cancel'))),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(ctrl.text.trim())),
            child: Text(s.t('save')),
          ),
        ],
      ),
    );
    if (result == null) return;
    final db = ref.read(databaseProvider);
    if (result < 0) {
      if (existing != null) {
        await (db.delete(db.budgets)
              ..where((b) => b.id.equals(existing.id)))
            .go();
      }
      return;
    }
    final paisa = (result * 100).round();
    if (existing == null) {
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            categoryId: Value(category?.id),
            limitPaisa: paisa,
          ));
    } else {
      await (db.update(db.budgets)..where((b) => b.id.equals(existing.id)))
          .write(BudgetsCompanion(limitPaisa: Value(paisa)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final budgets = ref.watch(budgetsProvider).value ?? [];
    final categories = ref.watch(categoriesProvider).value ?? [];
    final txs = ref.watch(transactionsProvider).value ?? [];
    final now = DateTime.now();
    final overall = budgets.where((b) => b.categoryId == null).firstOrNull;
    final totalExpense = monthSum(txs, 'expense', now);
    final expenseCats =
        categories.where((c) => c.kind == 'expense').toList();

    int spentFor(int? categoryId) {
      var sum = 0;
      for (final t in activeTx(txs)) {
        if (t.type == 'expense' &&
            t.categoryId == categoryId &&
            t.occurredAt.year == now.year &&
            t.occurredAt.month == now.month) {
          sum += t.amountPaisa;
        }
      }
      return sum;
    }

    Widget budgetBar(int spent, int limit) {
      final pct = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
      final color = pct >= 1
          ? HisablyColors.expense
          : pct >= 0.9
              ? HisablyColors.warning
              : pct >= 0.7
                  ? HisablyColors.warning
                  : HisablyColors.accent;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 9,
              backgroundColor: HisablyColors.input,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${formatPaisa(spent)} of ${formatPaisa(limit)} · ${(pct * 100).round()}%',
            style: const TextStyle(
                color: HisablyColors.textSecondary, fontSize: 12),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.t('budgets'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.t('overallBudget'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      TextButton(
                        onPressed: () =>
                            _editBudget(context, ref, existing: overall),
                        child: Text(overall == null ? s.t('set') : s.t('edit')),
                      ),
                    ],
                  ),
                  if (overall == null)
                    Text(s.t('noOverallBudget'),
                        style: const TextStyle(
                            color: HisablyColors.textSecondary))
                  else
                    budgetBar(totalExpense, overall.limitPaisa),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(s.t('categoryBudgets'),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final cat in expenseCats) ...[
            Builder(builder: (context) {
              final b =
                  budgets.where((x) => x.categoryId == cat.id).firstOrNull;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(cat.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          TextButton(
                            onPressed: () => _editBudget(context, ref,
                                existing: b, category: cat),
                            child: Text(b == null ? s.t('set') : s.t('edit')),
                          ),
                        ],
                      ),
                      if (b == null)
                        Text('${s.t('spentThisMonth')}: ${formatPaisa(spentFor(cat.id))}',
                            style: const TextStyle(
                                color: HisablyColors.textSecondary,
                                fontSize: 12))
                      else
                        budgetBar(spentFor(cat.id), b.limitPaisa),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
