import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import 'add_transaction_screen.dart';

const _labels = <String, (String, Color)>{
  'income': ('IN', HisablyColors.income),
  'expense': ('OUT', HisablyColors.orangeDark),
  'transfer': ('TRANSFER', HisablyColors.transfer),
  'lend': ('LEND', HisablyColors.savings),
  'borrow': ('BORROW', HisablyColors.warning),
  'lend_repay': ('REPAY IN', HisablyColors.income),
  'borrow_repay': ('REPAY OUT', HisablyColors.orangeDark),
  'reversal': ('REVERSAL', HisablyColors.textSecondary),
  'saving': ('SAVING', HisablyColors.savings),
  'saving_withdraw': ('WITHDRAW', HisablyColors.warning),
};

/// Type badges are ICONS, not text (v0.6.4) — words like BORROW and
/// REVERSAL wrapped and broke inside the small circle.
const _icons = <String, (IconData, Color)>{
  'income': (Icons.arrow_downward_rounded, HisablyColors.income),
  'expense': (Icons.arrow_upward_rounded, HisablyColors.orangeDark),
  'transfer': (Icons.swap_horiz_rounded, HisablyColors.transfer),
  'lend': (Icons.north_east_rounded, HisablyColors.savings),
  'borrow': (Icons.south_west_rounded, HisablyColors.warning),
  'lend_repay': (Icons.south_east_rounded, HisablyColors.income),
  'borrow_repay': (Icons.north_west_rounded, HisablyColors.orangeDark),
  'reversal': (Icons.undo_rounded, HisablyColors.textSecondary),
  'saving': (Icons.savings_rounded, HisablyColors.savings),
  'saving_withdraw': (Icons.arrow_circle_up_rounded, HisablyColors.warning),
};

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(transactionsProvider);
    final categories = ref.watch(categoriesProvider).value ?? [];
    final persons = ref.watch(personsProvider).value ?? [];
    final goals = ref.watch(savingsGoalsProvider).value ?? [];
    String catName(int? id) =>
        categories.where((c) => c.id == id).firstOrNull?.name ?? '';
    String personName(int? id) =>
        persons.where((p) => p.id == id).firstOrNull?.name ?? '';
    String goalName(int? id) =>
        goals.where((g) => g.id == id).firstOrNull?.name ?? '';

    return SafeArea(
      child: txs.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Text('No transactions yet.\nTap + Add to record the first one.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = list[i];
              final (label, color) =
                  _labels[t.type] ?? (t.type.toUpperCase(), Colors.grey);
              final (icon, iconColor) = _icons[t.type] ??
                  (Icons.receipt_long_rounded, Colors.grey);
              final title = t.personId != null
                  ? personName(t.personId)
                  : (catName(t.categoryId).isNotEmpty
                      ? catName(t.categoryId)
                      : (goalName(t.savingsGoalId).isNotEmpty
                          ? goalName(t.savingsGoalId)
                          : label));
              return Card(
                child: ListTile(
                  onTap: () => _showActions(context, ref, t, title),
                  onLongPress: () => _showActions(context, ref, t, title),
                  leading: CircleAvatar(
                    backgroundColor: iconColor.withValues(alpha: 0.14),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  title: Text(title,
                      style: TextStyle(
                        decoration:
                            t.isReversed ? TextDecoration.lineThrough : null,
                        fontWeight: FontWeight.w600,
                      )),
                  subtitle: Text(
                    [
                      DateFormat('d MMM, h:mm a').format(t.occurredAt),
                      if (t.note.isNotEmpty) t.note,
                      if (t.isReversed) 'reversed — tap history kept',
                    ].join(' · '),
                  ),
                  trailing: Text(
                    formatPaisa(t.amountPaisa),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      decoration:
                          t.isReversed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  /// Actions for one entry (v0.6.4): Edit and Reverse on active
  /// entries; Delete on a reversed entry (removes it together with its
  /// reversal record); Cancel always.
  Future<void> _showActions(
      BuildContext context, WidgetRef ref, Transaction t, String title) async {
    final s = ref.read(stringsProvider);
    final isActive = !t.isReversed && t.type != 'reversal';
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text(formatPaisa(t.amountPaisa),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Divider(height: 1),
            if (isActive) ...[
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text(s.t('edit')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AddTransactionScreen(editing: t)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.undo_rounded),
                title: Text(s.t('reverse')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmReverse(context, ref, t);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_rounded,
                    color: HisablyColors.expense),
                title: Text(s.t('delete'),
                    style: const TextStyle(color: HisablyColors.expense)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDeleteEntry(context, ref, t);
                },
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.delete_rounded,
                    color: HisablyColors.expense),
                title: Text(s.t('delete'),
                    style: const TextStyle(color: HisablyColors.expense)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDelete(context, ref, t);
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: Text(s.t('cancel')),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Transaction t) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('deletePairTitle')),
        content: Text(s.t('deletePairBody')),
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
    if (ok == true) {
      await ref.read(repositoryProvider).deleteReversedPair(t.id);
    }
  }

  /// Hard delete of one ACTIVE entry (Edit's counterpart). The
  /// repository guards Khata/savings consistency; its refusal
  /// message is shown as-is.
  Future<void> _confirmDeleteEntry(
      BuildContext context, WidgetRef ref, Transaction t) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('deleteEntryTitle')),
        content: Text(s.t('deleteEntryBody')),
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
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).deleteTransaction(t.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e
                .toString()
                .replaceFirst(RegExp(r'^(StateError|Bad state):?\s*'), ''))));
      }
    }
  }

  Future<void> _confirmReverse(
      BuildContext context, WidgetRef ref, Transaction t) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('reverseTitle')),
        content: const Text(
            'The entry will be marked reversed and a reversal record will be '
            'added. Nothing is deleted — the history stays visible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('reverse'))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(repositoryProvider).reverseTransaction(t.id);
    }
  }
}
