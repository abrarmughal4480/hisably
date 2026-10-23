import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import '../widgets/hisably_dropdown.dart';

/// Savings section (v0.6.4): goals with targets. Money moves into a
/// goal as a 'saving' transaction (out of an account, into the goal)
/// and back as 'saving_withdraw' — so account balances and the goal
/// totals always agree, and every move shows in Transactions.
class SavingsScreen extends ConsumerWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final goals = ref.watch(savingsGoalsProvider);
    final txs = ref.watch(transactionsProvider).value ?? [];
    final index = ref.watch(ledgerIndexProvider);
    final accounts = ref.watch(accountsProvider).value ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(s.t('savings'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(s.t('savings'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  FilledButton.icon(
                    onPressed: () => _newGoal(context, ref),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(s.t('newGoal')),
                    style: FilledButton.styleFrom(
                        backgroundColor: HisablyColors.primary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: goals.when(
                data: (list) {
                  if (list.isEmpty) {
                    return Center(
                      child: Text(s.t('noGoals'),
                          textAlign: TextAlign.center),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final goal = list[i];
                      final saved = index?.goalSavedOf(goal.id) ??
                          goalSavedOf(goal.id, txs);
                      final hasTarget = goal.targetPaisa > 0;
                      final pct = hasTarget
                          ? (saved / goal.targetPaisa * 100).floor()
                          : null;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.savings_rounded,
                                      color: HisablyColors.savings, size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(goal.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16)),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20),
                                    onPressed: () =>
                                        _deleteGoal(context, ref, goal),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                hasTarget
                                    ? '${s.t('savedLabel')}: ${formatPaisa(saved)} / ${formatPaisa(goal.targetPaisa)}${pct != null ? '  ·  $pct%' : ''}'
                                    : '${s.t('savedLabel')}: ${formatPaisa(saved)}',
                                style: const TextStyle(
                                    color: HisablyColors.textSecondary),
                              ),
                              if (hasTarget) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: (saved / goal.targetPaisa)
                                        .clamp(0.0, 1.0),
                                    minHeight: 8,
                                    backgroundColor: HisablyColors.elevated,
                                    color: HisablyColors.savings,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: accounts.isEmpty
                                        ? null
                                        : () => _moveMoney(context, ref,
                                            goal, accounts,
                                            withdraw: false),
                                    icon: const Icon(Icons.add_rounded,
                                        size: 18),
                                    label: Text(s.t('addMoney')),
                                  ),
                                  TextButton.icon(
                                    onPressed: (accounts.isEmpty || saved <= 0)
                                        ? null
                                        : () => _moveMoney(context, ref,
                                            goal, accounts,
                                            withdraw: true),
                                    icon: const Icon(Icons.remove_rounded,
                                        size: 18),
                                    label: Text(s.t('withdraw')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _clean(Object e) =>
      e.toString().replaceFirst(RegExp(r'^(StateError|Bad state):?\s*'), '');

  Future<void> _newGoal(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final nameCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('newGoal')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(labelText: s.t('goalName')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: targetCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: s.t('targetAmount')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('add'))),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final target = ((double.tryParse(targetCtrl.text.trim()) ?? 0) * 100)
        .round();
    await ref.read(repositoryProvider).addGoal(name, target);
  }

  Future<void> _moveMoney(BuildContext context, WidgetRef ref,
      SavingsGoal goal, List<Account> accounts,
      {required bool withdraw}) async {
    final s = ref.read(stringsProvider);
    final amountCtrl = TextEditingController();
    var accountId = accounts.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t(withdraw ? 'withdraw' : 'addMoney')),
        content: StatefulBuilder(
          builder: (context, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HisablyDropdown<int>(
                label: s.t(withdraw ? 'toAccountLabel' : 'fromAccount'),
                value: accountId,
                items: [
                  for (final a in accounts)
                    HisablyDropdownItem(value: a.id, label: a.name),
                ],
                onChanged: (v) => setLocal(() => accountId = v ?? accountId),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: s.t('amount'),
                    prefixText: 'Rs ',
                    border: const OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('save'))),
        ],
      ),
    );
    if (ok != true) return;
    final rupees = double.tryParse(amountCtrl.text.trim());
    if (rupees == null || rupees <= 0) {
      if (context.mounted) _snack(context, s.t('enterValidAmount'));
      return;
    }
    try {
      await ref.read(repositoryProvider).addTransaction(
            TransactionsCompanion.insert(
              type: withdraw ? 'saving_withdraw' : 'saving',
              amountPaisa: (rupees * 100).round(),
              accountId: accountId,
              savingsGoalId: Value(goal.id),
              note: Value(goal.name),
              occurredAt: DateTime.now(),
              createdAt: DateTime.now(),
            ),
          );
    } catch (e) {
      if (context.mounted) _snack(context, _clean(e));
    }
  }

  Future<void> _deleteGoal(
      BuildContext context, WidgetRef ref, SavingsGoal goal) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('deleteGoalTitle')),
        content: Text(goal.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                  backgroundColor: HisablyColors.expense),
              child: Text(s.t('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).deleteGoal(goal.id);
    } catch (e) {
      if (context.mounted) _snack(context, _clean(e));
    }
  }
}
