import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Wallets/accounts: Cash, Bank, JazzCash, EasyPaisa, Card, Savings...
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get type => text().withLength(min: 1, max: 20)(); // cash|bank|jazzcash|easypaisa|card|savings|other
  IntColumn get openingPaisa => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get kind => text().withLength(min: 1, max: 10)(); // income|expense|both
  TextColumn get icon => text().withDefault(const Constant('category'))();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// People for the Khata (udhaar) book.
class Persons extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
}

/// One table for every money movement. Money is ALWAYS integer paisa.
/// type: income | expense | transfer | lend | borrow | lend_repay | borrow_repay | reversal
/// Khata rules live in the repository: a lend is not an expense, a borrow is
/// not income, repayments are capped at the outstanding amount, and edits are
/// reversal entries — originals are never silently mutated.
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text().withLength(min: 1, max: 16)();
  IntColumn get amountPaisa => integer()(); // always > 0
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get toAccountId => integer().nullable().references(Accounts, #id)(); // transfers only
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  IntColumn get personId => integer().nullable().references(Persons, #id)(); // khata types only
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get reversesId => integer().nullable().references(Transactions, #id)(); // set on reversal entries
  BoolColumn get isReversed => boolean().withDefault(const Constant(false))();
  IntColumn get savingsGoalId => integer().nullable().references(SavingsGoals, #id)(); // saving types only (schema v2)
}

/// Savings goals (v0.6.4). Money moves into a goal with a 'saving'
/// transaction (account -, goal +) and back with 'saving_withdraw'.
class SavingsGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get targetPaisa => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)(); // null = overall monthly budget
  IntColumn get limitPaisa => integer()();
}

@DriftDatabase(
    tables: [Accounts, Categories, Transactions, Persons, Budgets, SavingsGoals])
class HisablyDatabase extends _$HisablyDatabase {
  HisablyDatabase() : super(_openConnection());
  HisablyDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(savingsGoals);
            await m.addColumn(transactions, transactions.savingsGoalId);
          }
        },
        beforeOpen: (details) async {
          // Retrieval speed (v0.6.8): indexes on the columns every
          // query filters or orders by. IF NOT EXISTS keeps this a
          // no-op after the first open.
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_tx_occurred ON transactions (occurred_at)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions (account_id)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_tx_person ON transactions (person_id)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions (type)');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'hisably.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
