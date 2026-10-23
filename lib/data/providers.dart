import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';
import 'ledger_index.dart';
import 'repository.dart';

export 'ledger_index.dart'
    show activeEntries, deltaForAccount, involvesAccount;

final databaseProvider = Provider<HisablyDatabase>((ref) {
  final db = HisablyDatabase();
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = Provider<LedgerRepository>((ref) {
  return LedgerRepository(ref.watch(databaseProvider));
});

/// Formats integer paisa as "Rs 1,23,456" (Indian/Pakistani digit grouping).
String formatPaisa(int paisa, {bool showSign = false}) {
  final negative = paisa < 0;
  final abs = paisa.abs();
  final rupees = abs ~/ 100;
  final rem = abs % 100;
  final grouped = _indianGroup(rupees.toString());
  final base = rem == 0 ? grouped : '$grouped.${rem.toString().padLeft(2, '0')}';
  final sign = negative ? '-' : (showSign ? '+' : '');
  return '${sign}Rs $base';
}

String _indianGroup(String digits) {
  if (digits.length <= 3) return digits;
  final head = digits.substring(0, digits.length - 3);
  final tail = digits.substring(digits.length - 3);
  final parts = <String>[];
  var h = head;
  while (h.length > 2) {
    parts.insert(0, h.substring(h.length - 2));
    h = h.substring(0, h.length - 2);
  }
  if (h.isNotEmpty) parts.insert(0, h);
  return '${parts.join(',')},$tail';
}

final accountsProvider = StreamProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)
        ..where((a) => a.isArchived.equals(false))
        ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
      .watch();
});

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.categories)
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
      .watch();
});

final personsProvider = StreamProvider<List<Person>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.persons)..orderBy([(p) => OrderingTerm.asc(p.name)]))
      .watch();
});

final transactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.transactions)
        ..orderBy([
          (t) => OrderingTerm.desc(t.occurredAt),
          (t) => OrderingTerm.desc(t.id),
        ]))
      .watch();
});

/// Pure derived helpers over watched rows. The math lives in the
/// ledger_index module (single source of truth); these wrappers keep
/// the long-standing call sites and tests working, while screens that
/// render lists should prefer [ledgerIndexProvider] — one O(n) build
/// with O(1) lookups instead of a full rescan per row.
List<Transaction> activeTx(List<Transaction> all) =>
    all.where((t) => !t.isReversed && t.type != 'reversal').toList();

/// The shared ledger index: rebuilt once per data change, then every
/// balance / outstanding / goal / monthly lookup is a map read.
final ledgerIndexProvider = Provider<LedgerIndex?>((ref) {
  final txs = ref.watch(transactionsProvider).value;
  final accounts = ref.watch(accountsProvider).value;
  if (txs == null || accounts == null) return null;
  return LedgerIndex.build(txs, accounts);
});

/// Compact money label for chart axes: Rs 950, Rs 4.5k, Rs 2.3L.
String formatCompact(int paisa) {
  final rupees = paisa / 100;
  final sign = rupees < 0 ? '-' : '';
  final abs = rupees.abs();
  if (abs >= 100000) return '${sign}Rs ${(abs / 100000).toStringAsFixed(1)}L';
  if (abs >= 1000) return '${sign}Rs ${(abs / 1000).toStringAsFixed(1)}k';
  return '${sign}Rs ${abs.toStringAsFixed(0)}';
}

int balanceOf(Account account, List<Transaction> all) =>
    LedgerIndex.build(all, [account]).balanceOf(account.id);

/// Per-person Khata totals (active entries only): how much was lent,
/// borrowed, and repaid in each direction — the "who took what, who
/// returned what, what is still pending" breakdown.
({int lent, int borrowed, int lendRepaid, int borrowRepaid}) personSummary(
    int personId, List<Transaction> all) {
  final t = LedgerIndex.build(all, const []).personTotals(personId);
  return (
    lent: t.lent,
    borrowed: t.borrowed,
    lendRepaid: t.lendRepaid,
    borrowRepaid: t.borrowRepaid
  );
}

int outstandingOf(int personId, List<Transaction> all) =>
    LedgerIndex.build(all, const []).outstandingOf(personId);

int monthSum(List<Transaction> all, String type, DateTime month) =>
    LedgerIndex.build(all, const []).monthSum(type, month);

final budgetsProvider = StreamProvider<List<Budget>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.budgets).watch();
});

final savingsGoalsProvider = StreamProvider<List<SavingsGoal>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.savingsGoals)
        ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
      .watch();
});

/// Amount currently set aside in a goal, folded from watched rows —
/// same rules as LedgerRepository.goalSavedPaisa.
int goalSavedOf(int goalId, List<Transaction> all) =>
    LedgerIndex.build(all, const []).goalSavedOf(goalId);
