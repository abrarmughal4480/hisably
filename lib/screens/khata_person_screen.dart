import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import 'add_transaction_screen.dart';

const _icons = <String, (IconData, Color)>{
  'lend': (Icons.north_east_rounded, HisablyColors.savings),
  'borrow': (Icons.south_west_rounded, HisablyColors.warning),
  'lend_repay': (Icons.south_east_rounded, HisablyColors.income),
  'borrow_repay': (Icons.north_west_rounded, HisablyColors.orangeDark),
  'reversal': (Icons.undo_rounded, HisablyColors.textSecondary),
};

const _typeNames = <String, String>{
  'lend': 'Lent',
  'borrow': 'Borrowed',
  'lend_repay': 'Repayment received',
  'borrow_repay': 'Repayment returned',
  'reversal': 'Reversal',
};

/// One person's Khata detail (v0.6.6): who took whose money, how much
/// came back, and what is still pending — in plain words — plus the
/// full entry history and one-tap Return / Receive actions.
class KhataPersonScreen extends ConsumerWidget {
  const KhataPersonScreen({super.key, required this.person});
  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    // Live row for this person, so edits made here show at once.
    var me = person;
    for (final p in ref.watch(personsProvider).value ?? <Person>[]) {
      if (p.id == person.id) me = p;
    }
    final all = ref.watch(transactionsProvider).value ?? [];
    final index = ref.watch(ledgerIndexProvider);
    // History shows every entry for this person — including reversed
    // ones (struck through) — newest first, as the provider orders.
    final mine = all.where((t) => t.personId == person.id).toList();
    final totals = index?.personTotals(person.id);
    final sum = totals == null
        ? personSummary(person.id, all)
        : (
            lent: totals.lent,
            borrowed: totals.borrowed,
            lendRepaid: totals.lendRepaid,
            borrowRepaid: totals.borrowRepaid
          );
    final net = index?.outstandingOf(person.id) ?? outstandingOf(person.id, all);
    final borrowRemaining = sum.borrowed - sum.borrowRepaid;
    final lendRemaining = sum.lent - sum.lendRepaid;

    final status = net == 0
        ? '${s.t('allSettledWith')} ${me.name}'
        : net < 0
            ? '${s.t('youHaveToReturn')} ${formatPaisa(-net)} to ${me.name}'
            : '${me.name} ${s.t('hasToReturnToYou')} ${formatPaisa(net)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(me.name),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'edit') _editPerson(context, ref, me);
              if (v == 'delete') _deletePerson(context, ref, me);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(s.t('editPerson'))),
              PopupMenuItem(
                value: 'delete',
                child: Text(s.t('deletePerson'),
                    style: const TextStyle(color: HisablyColors.expense)),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: net == 0
                              ? HisablyColors.text
                              : net < 0
                                  ? HisablyColors.expense
                                  : HisablyColors.income,
                        )),
                    if (sum.borrowed > 0 || sum.borrowRepaid > 0) ...[
                      const SizedBox(height: 14),
                      _row(s.t('borrowedFromThem'), formatPaisa(sum.borrowed)),
                      _row(s.t('youReturned'), formatPaisa(sum.borrowRepaid)),
                      _row(s.t('stillToReturn'), formatPaisa(borrowRemaining),
                          bold: true),
                    ],
                    if (sum.lent > 0 || sum.lendRepaid > 0) ...[
                      const SizedBox(height: 14),
                      _row(s.t('lentToThem'), formatPaisa(sum.lent)),
                      _row(s.t('receivedBackLabel'),
                          formatPaisa(sum.lendRepaid)),
                      _row(s.t('stillToReceive'), formatPaisa(lendRemaining),
                          bold: true),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      children: [
                        if (borrowRemaining > 0)
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AddTransactionScreen(
                                  presetType: 'borrow_repay',
                                  presetPersonId: person.id,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.north_west_rounded,
                                size: 18),
                            label: Text(s.t('returnMoney')),
                            style: FilledButton.styleFrom(
                                backgroundColor: HisablyColors.primary),
                          ),
                        if (lendRemaining > 0)
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AddTransactionScreen(
                                  presetType: 'lend_repay',
                                  presetPersonId: person.id,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.south_east_rounded,
                                size: 18),
                            label: Text(s.t('receiveBackBtn')),
                            style: FilledButton.styleFrom(
                                backgroundColor: HisablyColors.primary),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(s.t('history'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (mine.isEmpty)
              Text(s.t('noTransactions'),
                  style:
                      const TextStyle(color: HisablyColors.textSecondary)),
            for (final t in mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: (_icons[t.type]?.$2 ??
                              HisablyColors.textSecondary)
                          .withValues(alpha: 0.14),
                      child: Icon(
                          _icons[t.type]?.$1 ?? Icons.receipt_long_rounded,
                          color: _icons[t.type]?.$2 ??
                              HisablyColors.textSecondary,
                          size: 20),
                    ),
                    title: Text(_typeNames[t.type] ?? t.type,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: t.isReversed
                              ? TextDecoration.lineThrough
                              : null,
                        )),
                    subtitle: Text(
                      [
                        DateFormat('d MMM, h:mm a').format(t.occurredAt),
                        if (t.note.isNotEmpty) t.note,
                      ].join(' · '),
                    ),
                    trailing: Text(formatPaisa(t.amountPaisa),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration: t.isReversed
                              ? TextDecoration.lineThrough
                              : null,
                        )),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPerson(
      BuildContext context, WidgetRef ref, Person me) async {
    final s = ref.read(stringsProvider);
    final nameCtrl = TextEditingController(text: me.name);
    final phoneCtrl = TextEditingController(text: me.phone);
    final noteCtrl = TextEditingController(text: me.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('editPerson')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: s.t('name'))),
              const SizedBox(height: 10),
              TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: s.t('phone'))),
              const SizedBox(height: 10),
              TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(labelText: s.t('note'))),
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
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).updatePerson(me.id,
          name: nameCtrl.text, phone: phoneCtrl.text, note: noteCtrl.text);
    } catch (e) {
      if (context.mounted) _snack(context, e);
    }
  }

  Future<void> _deletePerson(
      BuildContext context, WidgetRef ref, Person me) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('deletePersonTitle')),
        content: Text(s.t('deletePersonBody')),
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
      await ref.read(repositoryProvider).deletePerson(me.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) _snack(context, e);
    }
  }

  void _snack(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e
            .toString()
            .replaceFirst(RegExp(r'^(StateError|Bad state):?\s*'), ''))));
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                  color: HisablyColors.textSecondary,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                )),
          ),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }
}
