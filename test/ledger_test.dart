import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/providers.dart';
import 'package:hisably/data/repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;

void main() {
  late HisablyDatabase db;
  late LedgerRepository repo;
  late int cashId;
  late int ahmedId;

  TransactionsCompanion tx(String type, int paisa,
      {int? personId, int? toAccountId}) {
    return TransactionsCompanion.insert(
      type: type,
      amountPaisa: paisa,
      accountId: cashId,
      personId: Value(personId),
      toAccountId: Value(toAccountId),
      occurredAt: DateTime(2026, 10, 21),
      createdAt: DateTime(2026, 10, 21),
    );
  }

  setUp(() async {
    db = HisablyDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
    await repo.seedCategoriesIfEmpty();
    // Accounts are user-added only in the final design — no defaults.
    expect(await db.select(db.accounts).get(), isEmpty);
    cashId = await repo.addAccount('Cash');
    ahmedId = await db.into(db.persons).insert(PersonsCompanion.insert(
          name: 'Ahmed',
          createdAt: DateTime(2026, 10, 21),
        ));
  });

  tearDown(() async => db.close());

  test('income adds, expense subtracts, balances use integer paisa', () async {
    await repo.addTransaction(tx('income', 15000000)); // Rs 150,000
    await repo.addTransaction(tx('expense', 6575000)); // Rs 65,750
    expect(await repo.accountBalancePaisa(cashId), 8425000);
  });

  test('lend is not an expense: cash drops, Lenay rises, income/expense totals unaffected', () async {
    await repo.addTransaction(tx('income', 15000000));
    await repo.addTransaction(tx('lend', 1500000, personId: ahmedId));
    expect(await repo.accountBalancePaisa(cashId), 13500000);
    expect(await repo.totalLenayPaisa(), 1500000);
    expect(await repo.totalDenayPaisa(), 0);
  });

  test('repayment is capped at outstanding', () async {
    await repo.addTransaction(tx('lend', 1500000, personId: ahmedId));
    await repo.addTransaction(tx('lend_repay', 300000, personId: ahmedId));
    expect(await repo.personOutstandingPaisa(ahmedId), 1200000);
    await expectLater(
      repo.addTransaction(tx('lend_repay', 1200001, personId: ahmedId)),
      throwsStateError,
    );
  });

  test('borrow creates Denay, not income', () async {
    await repo.addTransaction(tx('borrow', 700000, personId: ahmedId));
    expect(await repo.totalDenayPaisa(), 700000);
    expect(await repo.accountBalancePaisa(cashId), 700000);
  });

  test('reversal restores the balance and keeps history', () async {
    final id = await repo.addTransaction(tx('expense', 250000));
    expect(await repo.accountBalancePaisa(cashId), -250000);
    await repo.reverseTransaction(id);
    expect(await repo.accountBalancePaisa(cashId), 0);
    final all = await db.select(db.transactions).get();
    expect(all.length, 2); // original + reversal entry
    expect(all.first.isReversed, isTrue);
  });

  test('transfer moves money between accounts without changing the total', () async {
    final bankId = await repo.addAccount('HBL');
    await repo.addTransaction(tx('income', 1000000));
    await repo.addTransaction(tx('transfer', 400000, toAccountId: bankId));
    expect(await repo.accountBalancePaisa(cashId), 600000);
    expect(await repo.accountBalancePaisa(bankId), 400000);
  });

  test('edit fixes a wrong account and a wrong amount in place', () async {
    final jazzId = await repo.addAccount('JazzCash');
    final id = await repo.addTransaction(tx('expense', 50000)); // Rs 500 on Cash
    expect(await repo.accountBalancePaisa(cashId), -50000);
    await repo.updateTransaction(
      id: id,
      type: 'expense',
      amountPaisa: 75000,
      accountId: jazzId,
      note: 'fixed',
    );
    expect(await repo.accountBalancePaisa(cashId), 0);
    expect(await repo.accountBalancePaisa(jazzId), -75000);
    final row = await (db.select(db.transactions)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(row.note, 'fixed');
    expect(row.isReversed, isFalse);
  });

  test('edit cannot shrink a lend below what was already repaid', () async {
    final lendId =
        await repo.addTransaction(tx('lend', 100000, personId: ahmedId));
    await repo.addTransaction(tx('lend_repay', 80000, personId: ahmedId));
    expect(
      () => repo.updateTransaction(
        id: lendId,
        type: 'lend',
        amountPaisa: 50000,
        accountId: cashId,
        personId: ahmedId,
        note: '',
      ),
      throwsStateError,
    );
  });

  test('delete removes a reversed pair and never touches balances', () async {
    final id = await repo.addTransaction(tx('expense', 250000));
    await repo.reverseTransaction(id);
    expect(await repo.accountBalancePaisa(cashId), 0);
    await repo.deleteReversedPair(id);
    expect(await db.select(db.transactions).get(), isEmpty);
    expect(await repo.accountBalancePaisa(cashId), 0);
    // An active entry cannot be deleted.
    final activeId = await repo.addTransaction(tx('income', 1000));
    expect(() => repo.deleteReversedPair(activeId), throwsStateError);
  });

  test('savings: money moves account -> goal, withdraw is capped', () async {
    await repo.addTransaction(tx('income', 1000000));
    final goalId = await repo.addGoal('Bike', 500000);
    TransactionsCompanion save(String type, int paisa) {
      return TransactionsCompanion.insert(
        type: type,
        amountPaisa: paisa,
        accountId: cashId,
        savingsGoalId: Value(goalId),
        occurredAt: DateTime(2026, 10, 21),
        createdAt: DateTime(2026, 10, 21),
      );
    }

    await repo.addTransaction(save('saving', 300000));
    expect(await repo.accountBalancePaisa(cashId), 700000);
    expect(await repo.goalSavedPaisa(goalId), 300000);
    expect(
      () => repo.addTransaction(save('saving_withdraw', 300001)),
      throwsStateError,
    );
    await repo.addTransaction(save('saving_withdraw', 100000));
    expect(await repo.accountBalancePaisa(cashId), 800000);
    expect(await repo.goalSavedPaisa(goalId), 200000);
    // A goal with entries cannot be deleted.
    expect(() => repo.deleteGoal(goalId), throwsStateError);
  });

  test('person summary: taken, returned and still-pending per direction', () async {
    await repo.addTransaction(tx('borrow', 20000, personId: ahmedId)); // took Rs 200
    await repo.addTransaction(tx('borrow_repay', 5000, personId: ahmedId)); // returned Rs 50
    await repo.addTransaction(tx('lend', 100000, personId: ahmedId)); // gave Rs 1,000
    // One net per person: the Rs 150 the user still owes offsets the
    // lend, so Rs 850 is the most that can come back as lend_repay.
    await repo.addTransaction(tx('lend_repay', 85000, personId: ahmedId));
    final all = await db.select(db.transactions).get();
    final sum = personSummary(ahmedId, all);
    expect(sum.borrowed, 20000);
    expect(sum.borrowRepaid, 5000);
    expect(sum.borrowed - sum.borrowRepaid, 15000); // still to return Rs 150
    expect(sum.lent, 100000);
    expect(sum.lendRepaid, 85000);
    expect(sum.lent - sum.lendRepaid, 15000); // still to receive Rs 150
    expect(outstandingOf(ahmedId, all), 0); // the two remainders cancel out
  });

  test('default categories are pure English and old Roman names migrate', () async {
    final cats = await db.select(db.categories).get();
    expect(cats.map((c) => c.name), containsAll(['Food & Drink', 'Travel', 'Other', 'Other Income', 'Salary']));
    expect(cats.any((c) => c.name == 'Khana Peena'), isFalse);
    // Simulate an old install: rename back to Roman, then migrate.
    final food = cats.firstWhere((c) => c.name == 'Food & Drink');
    await (db.update(db.categories)..where((c) => c.id.equals(food.id)))
        .write(const CategoriesCompanion(name: Value('Khana Peena')));
    await repo.migrateCategoryNamesToEnglish();
    final after = await db.select(db.categories).get();
    expect(after.any((c) => c.name == 'Khana Peena'), isFalse);
    expect(after.any((c) => c.name == 'Food & Drink'), isTrue);
  });
}
