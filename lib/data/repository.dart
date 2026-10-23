import 'package:drift/drift.dart';

import 'category_catalog.dart';
import 'database.dart';
import 'ledger_index.dart';

/// All money logic in one place. Amounts are integer paisa, always > 0.
///
/// Sign conventions per account balance:
///   income + | expense - | transfer out - / in + | lend - (cash out, becomes
///   a receivable) | borrow + (cash in, becomes a payable) |
///   lend_repay + | borrow_repay -
/// Khata outstanding per person (what they owe the user, positive = Lenay):
///   lend + | borrow - | lend_repay - | borrow_repay +
/// Reversed originals and reversal entries are both excluded from totals.
class LedgerRepository {
  LedgerRepository(this.db);
  final HisablyDatabase db;

  // Sign rules live in the ledger_index module (single source of
  // truth, shared with the UI's indexed aggregates).
  static const _balanceSigns = txBalanceSigns;

  Future<int> accountBalancePaisa(int accountId) async {
    final acct = await (db.select(db.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingle();
    var balance = acct.openingPaisa;
    final rows = await (db.select(db.transactions)
          ..where((t) => t.isReversed.equals(false)))
        .get();
    for (final t in rows) {
      if (t.type == 'reversal') continue;
      if (t.type == 'transfer') {
        if (t.accountId == accountId) balance -= t.amountPaisa;
        if (t.toAccountId == accountId) balance += t.amountPaisa;
      } else if (t.accountId == accountId) {
        balance += (_balanceSigns[t.type] ?? 0) * t.amountPaisa;
      }
    }
    return balance;
  }

  /// Net position with one person. Positive = they owe the user (Lenay),
  /// negative = the user owes them (Denay).
  Future<int> personOutstandingPaisa(int personId) async {
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.personId.equals(personId) & t.isReversed.equals(false)))
        .get();
    var net = 0;
    for (final t in rows) {
      switch (t.type) {
        case 'lend':
        case 'borrow_repay':
          net += t.amountPaisa;
        case 'borrow':
        case 'lend_repay':
          net -= t.amountPaisa;
      }
    }
    return net;
  }

  Future<int> totalLenayPaisa() async {
    final people = await db.select(db.persons).get();
    var sum = 0;
    for (final person in people) {
      final net = await personOutstandingPaisa(person.id);
      if (net > 0) sum += net;
    }
    return sum;
  }

  Future<int> totalDenayPaisa() async {
    final people = await db.select(db.persons).get();
    var sum = 0;
    for (final person in people) {
      final net = await personOutstandingPaisa(person.id);
      if (net < 0) sum += -net;
    }
    return sum;
  }

  /// Adds a transaction after enforcing the Khata caps: a repayment can
  /// never exceed the outstanding amount in its direction.
  Future<int> addTransaction(TransactionsCompanion entry) async {
    final type = entry.type.value;
    final amount = entry.amountPaisa.value;
    if (amount <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }
    final personId = entry.personId.present ? entry.personId.value : null;
    if (type == 'lend_repay' || type == 'borrow_repay') {
      if (personId == null) {
        throw ArgumentError('Repayment needs a person');
      }
      final outstanding = await personOutstandingPaisa(personId);
      if (type == 'lend_repay' && amount > outstanding) {
        throw StateError('Repayment is more than the outstanding amount');
      }
      if (type == 'borrow_repay' && amount > -outstanding) {
        throw StateError('Repayment is more than the outstanding amount');
      }
    }
    if (type == 'saving' || type == 'saving_withdraw') {
      final goalId =
          entry.savingsGoalId.present ? entry.savingsGoalId.value : null;
      if (goalId == null) {
        throw ArgumentError('Saving entry needs a goal');
      }
      if (type == 'saving_withdraw' &&
          amount > await goalSavedPaisa(goalId)) {
        throw StateError('Withdrawal is more than the saved amount');
      }
    }
    return db.into(db.transactions).insert(entry);
  }

  /// How much is currently set aside in one savings goal.
  Future<int> goalSavedPaisa(int goalId) async {
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.savingsGoalId.equals(goalId) & t.isReversed.equals(false)))
        .get();
    var saved = 0;
    for (final t in rows) {
      if (t.type == 'saving') saved += t.amountPaisa;
      if (t.type == 'saving_withdraw') saved -= t.amountPaisa;
    }
    return saved;
  }

  Future<int> addGoal(String name, int targetPaisa) {
    return db.into(db.savingsGoals).insert(SavingsGoalsCompanion.insert(
          name: name.trim(),
          targetPaisa: Value(targetPaisa),
          createdAt: DateTime.now(),
        ));
  }

  /// A goal can only be deleted while it has no entries at all —
  /// money history is never wiped silently.
  Future<void> deleteGoal(int goalId) async {
    final rows = await (db.select(db.transactions)
          ..where((t) => t.savingsGoalId.equals(goalId)))
        .get();
    if (rows.isNotEmpty) {
      throw StateError(
          'This goal has entries — withdraw or reverse them first');
    }
    await (db.delete(db.savingsGoals)..where((g) => g.id.equals(goalId)))
        .go();
  }

  Future<({int lend, int borrow, int lendRepay, int borrowRepay})>
      _personTotals(int personId, {int? excludeId}) async {
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.personId.equals(personId) & t.isReversed.equals(false)))
        .get();
    var l = 0, b = 0, lr = 0, br = 0;
    for (final t in rows) {
      if (t.id == excludeId || t.type == 'reversal') continue;
      switch (t.type) {
        case 'lend':
          l += t.amountPaisa;
        case 'borrow':
          b += t.amountPaisa;
        case 'lend_repay':
          lr += t.amountPaisa;
        case 'borrow_repay':
          br += t.amountPaisa;
      }
    }
    return (lend: l, borrow: b, lendRepay: lr, borrowRepay: br);
  }

  /// Edit-time Khata guard: after the edit, repayments must still not
  /// exceed what they repay, in either direction.
  void _validateKhata(
    ({int lend, int borrow, int lendRepay, int borrowRepay}) totals,
    String type,
    int amount,
  ) {
    var l = totals.lend, b = totals.borrow, lr = totals.lendRepay, br = totals.borrowRepay;
    switch (type) {
      case 'lend':
        l += amount;
      case 'borrow':
        b += amount;
      case 'lend_repay':
        lr += amount;
      case 'borrow_repay':
        br += amount;
    }
    final netExcl =
        totals.lend - totals.borrow - totals.lendRepay + totals.borrowRepay;
    if (type == 'lend_repay' && amount > netExcl) {
      throw StateError('Repayment is more than the outstanding amount');
    }
    if (type == 'borrow_repay' && amount > -netExcl) {
      throw StateError('Repayment is more than the outstanding amount');
    }
    if (lr > l + br) {
      throw StateError('Repaid amount would exceed the lent amount');
    }
    if (br > b + lr) {
      throw StateError('Repaid amount would exceed the borrowed amount');
    }
  }

  /// Edits an active transaction in place (user request, v0.6.4 — e.g.
  /// fixing a wrong account). Balances are derived from the rows, so
  /// they follow the edit automatically. Reversed entries and reversal
  /// records are audit history and cannot be edited. Khata and savings
  /// caps are re-validated against the edited values.
  Future<void> updateTransaction({
    required int id,
    required String type,
    required int amountPaisa,
    required int accountId,
    int? toAccountId,
    int? categoryId,
    int? personId,
    int? savingsGoalId,
    required String note,
    DateTime? occurredAt,
  }) async {
    if (amountPaisa <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }
    await db.transaction(() async {
      final original = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      if (original.isReversed || original.type == 'reversal') {
        throw StateError('A reversed entry cannot be edited');
      }
      if (personId != null) {
        _validateKhata(
            await _personTotals(personId, excludeId: id), type, amountPaisa);
      }
      if (original.personId != null && original.personId != personId) {
        // The old person's books must stay consistent without this row.
        _validateKhata(
            await _personTotals(original.personId!, excludeId: id),
            '',
            0);
      }
      if (type == 'saving_withdraw') {
        final goalId = savingsGoalId ?? original.savingsGoalId;
        if (goalId == null) {
          throw ArgumentError('Saving entry needs a goal');
        }
        final rows = await (db.select(db.transactions)
              ..where((t) =>
                  t.savingsGoalId.equals(goalId) &
                  t.isReversed.equals(false)))
            .get();
        var savedExcl = 0;
        for (final t in rows) {
          if (t.id == id) continue;
          if (t.type == 'saving') savedExcl += t.amountPaisa;
          if (t.type == 'saving_withdraw') savedExcl -= t.amountPaisa;
        }
        if (amountPaisa > savedExcl) {
          throw StateError('Withdrawal is more than the saved amount');
        }
      }
      await (db.update(db.transactions)..where((t) => t.id.equals(id)))
          .write(TransactionsCompanion(
        type: Value(type),
        amountPaisa: Value(amountPaisa),
        accountId: Value(accountId),
        toAccountId: Value(toAccountId),
        categoryId: Value(categoryId),
        personId: Value(personId),
        savingsGoalId: Value(savingsGoalId),
        note: Value(note),
        occurredAt:
            occurredAt == null ? const Value.absent() : Value(occurredAt),
      ));
    });
  }

  /// Deletes a reversed entry together with its reversal record
  /// (user request, v0.6.4). Both rows are already excluded from every
  /// total, so balances never change. Active entries cannot be
  /// deleted — reverse them first.
  Future<void> deleteReversedPair(int transactionId) async {
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(transactionId)))
        .getSingle();
    int? originalId;
    int? reversalId;
    if (tx.type == 'reversal' && tx.reversesId != null) {
      reversalId = tx.id;
      originalId = tx.reversesId;
    } else if (tx.isReversed) {
      originalId = tx.id;
      final rev = await (db.select(db.transactions)
            ..where((t) => t.reversesId.equals(tx.id)))
          .getSingleOrNull();
      reversalId = rev?.id;
    } else {
      throw StateError('Only a reversed entry can be deleted');
    }
    await db.transaction(() async {
      if (reversalId != null) {
        await (db.delete(db.transactions)
              ..where((t) => t.id.equals(reversalId!)))
            .go();
      }
      if (originalId != null) {
        await (db.delete(db.transactions)
              ..where((t) => t.id.equals(originalId!)))
            .go();
      }
    });
  }

  /// The only way to "edit" history: mark the original reversed and append
  /// a reversal entry pointing back at it. Nothing is silently mutated.
  Future<void> reverseTransaction(int transactionId) async {
    final original = await (db.select(db.transactions)
          ..where((t) => t.id.equals(transactionId)))
        .getSingle();
    if (original.isReversed || original.type == 'reversal') {
      throw StateError('Transaction already reversed');
    }
    await db.transaction(() async {
      await (db.update(db.transactions)
            ..where((t) => t.id.equals(transactionId)))
          .write(const TransactionsCompanion(isReversed: Value(true)));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            type: 'reversal',
            amountPaisa: original.amountPaisa,
            accountId: original.accountId,
            toAccountId: Value(original.toAccountId),
            categoryId: Value(original.categoryId),
            personId: Value(original.personId),
            note: Value('Reversal of #${original.id}'),
            occurredAt: DateTime.now(),
            createdAt: DateTime.now(),
            reversesId: Value(original.id),
          ));
    });
  }

  /// Pure-English names for the default categories (user rule,
  /// 22 Oct 2026: "App ma pure English only, not Roman"). The map
  /// itself lives in the category catalog module.
  static const categoryRenames = CategoryCatalog.renames;

  /// One-time, idempotent rename of the built-in categories on
  /// existing installs so old data turns English too. Custom
  /// categories are never touched.
  Future<void> migrateCategoryNamesToEnglish() async {
    final existing = await db.select(db.categories).get();
    final names = existing.map((c) => c.name).toSet();
    await db.transaction(() async {
      for (final c in existing) {
        final english = categoryRenames[c.name];
        if (english == null || c.isCustom) continue;
        if (names.contains(english)) continue; // target already exists
        await (db.update(db.categories)..where((x) => x.id.equals(c.id)))
            .write(CategoriesCompanion(name: Value(english)));
        names
          ..remove(c.name)
          ..add(english);
      }
    });
  }

  /// First-run defaults: Pakistan categories, English names only.
  /// Accounts are NEVER seeded — the user adds their own
  /// (final design decision, 22 Oct 2026).
  Future<void> seedCategoriesIfEmpty() async {
    final existing = await db.select(db.categories).get();
    if (existing.isNotEmpty) return;
    await db.transaction(() async {
      const expense = CategoryCatalog.expenseNames;
      const income = CategoryCatalog.incomeNames;
      for (var i = 0; i < expense.length; i++) {
        await db.into(db.categories).insert(CategoriesCompanion.insert(
              name: expense[i],
              kind: 'expense',
              icon: Value(CategoryCatalog.iconForName[expense[i]] ?? 'category'),
              sortOrder: Value(i),
            ));
      }
      for (var i = 0; i < income.length; i++) {
        await db.into(db.categories).insert(CategoriesCompanion.insert(
              name: income[i],
              kind: 'income',
              icon: Value(CategoryCatalog.iconForName[income[i]] ?? 'category'),
              sortOrder: Value(i),
            ));
      }
    });
  }

  /// Gives every built-in category its proper icon on existing
  /// installs (older seeds stored the generic 'category' icon).
  /// Idempotent; custom categories are never touched.
  Future<void> assignCategoryIcons() async {
    final existing = await db.select(db.categories).get();
    await db.transaction(() async {
      for (final c in existing) {
        final icon = CategoryCatalog.iconForName[c.name];
        if (icon != null && !c.isCustom && c.icon != icon) {
          await (db.update(db.categories)..where((x) => x.id.equals(c.id)))
              .write(CategoriesCompanion(icon: Value(icon)));
        }
      }
    });
  }

  /// Adds a user account (name only; balance starts at zero).
  Future<int> addAccount(String name) async {
    final existing = await db.select(db.accounts).get();
    return db.into(db.accounts).insert(AccountsCompanion.insert(
          name: name.trim(),
          type: 'custom',
          sortOrder: Value(existing.length),
        ));
  }
}
