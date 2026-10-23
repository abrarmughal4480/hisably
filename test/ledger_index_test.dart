import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/ledger_index.dart';

Transaction _tx(
  int id,
  String type,
  int paisa, {
  int accountId = 1,
  int? toAccountId,
  int? categoryId,
  int? personId,
  int? savingsGoalId,
  bool isReversed = false,
  required DateTime at,
}) {
  return Transaction(
    id: id,
    type: type,
    amountPaisa: paisa,
    accountId: accountId,
    toAccountId: toAccountId,
    categoryId: categoryId,
    personId: personId,
    note: '',
    occurredAt: at,
    createdAt: at,
    reversesId: null,
    isReversed: isReversed,
    savingsGoalId: savingsGoalId,
  );
}

void main() {
  final cash = Account(
      id: 1,
      name: 'Cash',
      type: 'cash',
      openingPaisa: 100000,
      sortOrder: 0,
      isArchived: false);
  final jazz = Account(
      id: 2,
      name: 'JazzCash',
      type: 'jazzcash',
      openingPaisa: 0,
      sortOrder: 1,
      isArchived: false);

  final txs = <Transaction>[
    _tx(1, 'income', 50000, categoryId: 11, at: DateTime(2026, 8, 5)),
    _tx(2, 'expense', 10000, categoryId: 21, at: DateTime(2026, 10, 3)),
    _tx(3, 'expense', 5000, categoryId: 22, at: DateTime(2026, 10, 10)),
    _tx(4, 'transfer', 20000, toAccountId: 2, at: DateTime(2026, 10, 11)),
    _tx(5, 'lend', 30000, personId: 7, at: DateTime(2026, 10, 12)),
    _tx(6, 'borrow', 8000, personId: 8, at: DateTime(2026, 10, 13)),
    _tx(7, 'lend_repay', 12000, personId: 7, at: DateTime(2026, 10, 14)),
    _tx(8, 'saving', 7000, savingsGoalId: 3, at: DateTime(2026, 10, 15)),
    _tx(9, 'expense', 9999, isReversed: true, at: DateTime(2026, 10, 16)),
    _tx(10, 'reversal', 9999, at: DateTime(2026, 10, 16)),
  ];

  group('LedgerIndex', () {
    final index = LedgerIndex.build(txs, [cash, jazz]);

    test('balances fold openings, signs and transfers in one pass', () {
      // 100000 +50000 −10000 −5000 −20000 −30000 +8000 +12000 −7000
      expect(index.balanceOf(1), 98000);
      expect(index.balanceOf(2), 20000);
      expect(index.totalBalance(), 118000);
      expect(index.openingTotal, 100000);
    });

    test('khata nets and per-direction totals', () {
      expect(index.outstandingOf(7), 18000);
      expect(index.outstandingOf(8), -8000);
      final t7 = index.personTotals(7);
      expect(t7.lent, 30000);
      expect(t7.lendRepaid, 12000);
      expect(t7.lendRemaining, 18000);
      expect(index.personTotals(8).borrowRemaining, 8000);
    });

    test('goal totals and monthly sums', () {
      expect(index.goalSavedOf(3), 7000);
      expect(index.monthSum('expense', DateTime(2026, 10)), 15000);
      expect(index.monthSum('income', DateTime(2026, 8)), 50000);
      expect(index.monthSum('income', DateTime(2026, 10)), 0);
    });

    test('reversed originals and reversal rows never count', () {
      expect(index.active.length, 8);
      expect(index.monthSum('expense', DateTime(2026, 10)), 15000);
    });

    test('frequent combos rank by count, then recency, inside window', () {
      final top = index.frequent(now: DateTime(2026, 10, 22));
      expect(top.length, 3);
      // All counts are 1 → most recent first: Travel (10 Oct).
      expect(top.first.categoryId, 22);
      expect(top.first.lastAmountPaisa, 5000);
      // The August salary falls outside a 30-day window.
      final recent = index.frequent(now: DateTime(2026, 10, 22), withinDays: 30);
      expect(recent.map((c) => c.categoryId), isNot(contains(11)));
    });

    test('deltaForAccount: transfers cancel in the total view', () {
      final transfer = txs[3];
      expect(deltaForAccount(transfer, null), 0);
      expect(deltaForAccount(transfer, 1), -20000);
      expect(deltaForAccount(transfer, 2), 20000);
      expect(deltaForAccount(txs[0], null), 50000);
      expect(deltaForAccount(txs[0], 2), 0);
    });
  });
}
