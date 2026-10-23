import 'database.dart';

/// Fast, indexed view over the whole ledger (v0.6.8, modular data
/// layer). One O(n) pass over the active transactions builds hash maps
/// for every aggregate the UI needs — account balances, per-person
/// Khata positions, savings-goal totals, monthly income/expense sums
/// and frequent category combos — so each lookup afterwards is O(1)
/// instead of rescanning the full list for every row on screen.
///
/// Pure Dart over plain lists: no database, no Flutter. The sign rules
/// here are the single source of truth and mirror LedgerRepository:
/// account balance — income +, expense −, lend −, borrow +,
/// lend_repay +, borrow_repay −, saving −, saving_withdraw +,
/// transfers −from/+to; Khata net per person (positive = they owe the
/// user) — lend +, borrow −, lend_repay −, borrow_repay +.
/// Reversed originals and reversal rows never count.
const txBalanceSigns = <String, int>{
  'income': 1,
  'expense': -1,
  'lend': -1,
  'borrow': 1,
  'lend_repay': 1,
  'borrow_repay': -1,
  'saving': -1,
  'saving_withdraw': 1,
};

/// Entries that count toward every total, oldest first.
List<Transaction> activeEntries(List<Transaction> all) {
  final list =
      all.where((t) => !t.isReversed && t.type != 'reversal').toList();
  list.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  return list;
}

/// Whether a transaction touches an account (null accountId = all).
bool involvesAccount(Transaction t, int? accountId) =>
    accountId == null || t.accountId == accountId || t.toAccountId == accountId;

/// Signed effect of [t] on one account's balance — or, when
/// [accountId] is null, on the total across all accounts (transfers
/// cancel out there).
int deltaForAccount(Transaction t, int? accountId) {
  if (t.type == 'transfer') {
    if (accountId == null) return 0;
    if (t.accountId == accountId) return -t.amountPaisa;
    if (t.toAccountId == accountId) return t.amountPaisa;
    return 0;
  }
  if (accountId != null && t.accountId != accountId) return 0;
  return (txBalanceSigns[t.type] ?? 0) * t.amountPaisa;
}

/// Per-person Khata totals in both directions.
class PersonTotals {
  const PersonTotals({
    this.lent = 0,
    this.borrowed = 0,
    this.lendRepaid = 0,
    this.borrowRepaid = 0,
  });
  final int lent;
  final int borrowed;
  final int lendRepaid;
  final int borrowRepaid;

  /// Positive = the person owes the user; negative = the user owes them.
  int get net => lent + borrowRepaid - borrowed - lendRepaid;
  int get lendRemaining => lent - lendRepaid;
  int get borrowRemaining => borrowed - borrowRepaid;
}

/// A repeated (type, category) combination for one-tap repeats.
class FrequentCombo {
  const FrequentCombo({
    required this.type,
    required this.categoryId,
    required this.count,
    required this.lastAmountPaisa,
    required this.lastAt,
  });
  final String type;
  final int categoryId;
  final int count;
  final int lastAmountPaisa;
  final DateTime lastAt;
}

class LedgerIndex {
  LedgerIndex._(
    this.active,
    this._balances,
    this._personTotals,
    this._goalSaved,
    this._monthTypeSums,
    this._combos,
    this._openingTotal,
  );

  factory LedgerIndex.build(List<Transaction> all, List<Account> accounts) {
    final active = activeEntries(all);
    final balances = <int, int>{
      for (final a in accounts) a.id: a.openingPaisa,
    };
    final openingTotal =
        accounts.fold<int>(0, (sum, a) => sum + a.openingPaisa);
    final lent = <int, int>{};
    final borrowed = <int, int>{};
    final lendRepaid = <int, int>{};
    final borrowRepaid = <int, int>{};
    final goalSaved = <int, int>{};
    final monthTypeSums = <String, int>{};
    final comboCount = <String, int>{};
    final comboLastAmount = <String, int>{};
    final comboLastAt = <String, DateTime>{};

    void bump(Map<int, int> map, int key, int by) =>
        map[key] = (map[key] ?? 0) + by;

    for (final t in active) {
      // Balances (transfers move money between two accounts).
      if (t.type == 'transfer') {
        if (balances.containsKey(t.accountId)) {
          bump(balances, t.accountId, -t.amountPaisa);
        }
        final to = t.toAccountId;
        if (to != null && balances.containsKey(to)) {
          bump(balances, to, t.amountPaisa);
        }
      } else {
        if (balances.containsKey(t.accountId)) {
          bump(balances, t.accountId,
              (txBalanceSigns[t.type] ?? 0) * t.amountPaisa);
        }
      }
      // Khata per-person totals.
      final pid = t.personId;
      if (pid != null) {
        switch (t.type) {
          case 'lend':
            bump(lent, pid, t.amountPaisa);
          case 'borrow':
            bump(borrowed, pid, t.amountPaisa);
          case 'lend_repay':
            bump(lendRepaid, pid, t.amountPaisa);
          case 'borrow_repay':
            bump(borrowRepaid, pid, t.amountPaisa);
        }
      }
      // Savings goals.
      final gid = t.savingsGoalId;
      if (gid != null) {
        if (t.type == 'saving') bump(goalSaved, gid, t.amountPaisa);
        if (t.type == 'saving_withdraw') bump(goalSaved, gid, -t.amountPaisa);
      }
      // Monthly sums per type (reports read income/expense).
      final mk = '${t.type}|${t.occurredAt.year * 100 + t.occurredAt.month}';
      monthTypeSums[mk] = (monthTypeSums[mk] ?? 0) + t.amountPaisa;
      // Frequent combos for income/expense with a category.
      final cid = t.categoryId;
      if (cid != null && (t.type == 'income' || t.type == 'expense')) {
        final key = '${t.type}|$cid';
        comboCount[key] = (comboCount[key] ?? 0) + 1;
        // `active` is chronological, so the last write is the latest.
        comboLastAmount[key] = t.amountPaisa;
        comboLastAt[key] = t.occurredAt;
      }
    }

    final personTotals = <int, PersonTotals>{};
    final personIds = <int>{
      ...lent.keys,
      ...borrowed.keys,
      ...lendRepaid.keys,
      ...borrowRepaid.keys,
    };
    for (final id in personIds) {
      personTotals[id] = PersonTotals(
        lent: lent[id] ?? 0,
        borrowed: borrowed[id] ?? 0,
        lendRepaid: lendRepaid[id] ?? 0,
        borrowRepaid: borrowRepaid[id] ?? 0,
      );
    }

    final combos = <FrequentCombo>[
      for (final e in comboCount.entries)
        FrequentCombo(
          type: e.key.split('|').first,
          categoryId: int.parse(e.key.split('|').last),
          count: e.value,
          lastAmountPaisa: comboLastAmount[e.key] ?? 0,
          lastAt: comboLastAt[e.key] ?? DateTime(2000),
        ),
    ];

    return LedgerIndex._(active, balances, personTotals, goalSaved,
        monthTypeSums, combos, openingTotal);
  }

  /// Active entries only, oldest first.
  final List<Transaction> active;
  final Map<int, int> _balances;
  final Map<int, PersonTotals> _personTotals;
  final Map<int, int> _goalSaved;
  final Map<String, int> _monthTypeSums;
  final List<FrequentCombo> _combos;

  /// Sum of all account opening balances (the trend's starting point).
  final int _openingTotal;

  int balanceOf(int accountId) => _balances[accountId] ?? 0;

  /// Total across the given accounts (defaults to every account in the
  /// index) at the current end of history.
  int totalBalance() => _balances.values.fold(0, (a, b) => a + b);

  int get openingTotal => _openingTotal;

  PersonTotals personTotals(int personId) =>
      _personTotals[personId] ?? const PersonTotals();

  /// Positive = they owe the user; negative = the user owes them.
  int outstandingOf(int personId) => personTotals(personId).net;

  int goalSavedOf(int goalId) => _goalSaved[goalId] ?? 0;

  int monthSum(String type, DateTime month) =>
      _monthTypeSums['$type|${month.year * 100 + month.month}'] ?? 0;

  /// Most-repeated income/expense categories lately — for the Home
  /// one-tap repeat shortcuts. Sorted by count, then recency.
  List<FrequentCombo> frequent({
    int limit = 4,
    int withinDays = 90,
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(Duration(days: withinDays));
    final list = _combos.where((c) => !c.lastAt.isBefore(cutoff)).toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : b.lastAt.compareTo(a.lastAt);
      });
    return list.take(limit).toList();
  }
}
