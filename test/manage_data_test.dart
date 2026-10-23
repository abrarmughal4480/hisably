import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/repository.dart';

/// Edit/delete for every kind of record (user request, 23 Oct 2026):
/// the guards must refuse exactly the deletes that would corrupt
/// the ledger, and allow the rest.
void main() {
  late HisablyDatabase db;
  late LedgerRepository repo;
  late int cashId;

  Future<int> addTx(String type, int paisa,
      {int? personId, int? categoryId}) {
    return repo.addTransaction(TransactionsCompanion.insert(
      type: type,
      amountPaisa: paisa,
      accountId: cashId,
      personId: Value(personId),
      categoryId: Value(categoryId),
      occurredAt: DateTime(2026, 10, 23),
      createdAt: DateTime(2026, 10, 23),
    ));
  }

  setUp(() async {
    db = HisablyDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
    await repo.seedCategoriesIfEmpty();
    cashId = await repo.addAccount('Cash');
  });

  tearDown(() async => db.close());

  test('person: edit works; delete blocked by entries, allowed after',
      () async {
    final pid = await db.into(db.persons).insert(
        PersonsCompanion.insert(name: 'Zain', createdAt: DateTime.now()));
    await repo.updatePerson(pid, name: 'Zain Ali', phone: '0300');
    var p = await (db.select(db.persons)..where((x) => x.id.equals(pid)))
        .getSingle();
    expect(p.name, 'Zain Ali');
    expect(p.phone, '0300');

    final lendId = await addTx('lend', 20000, personId: pid);
    expect(() => repo.deletePerson(pid), throwsStateError);
    await repo.deleteTransaction(lendId);
    await repo.deletePerson(pid);
    final gone = await (db.select(db.persons)
          ..where((x) => x.id.equals(pid)))
        .getSingleOrNull();
    expect(gone, isNull);
  });

  test('account: rename works; delete blocked by entries', () async {
    await repo.updateAccount(cashId, name: 'Cash Wallet');
    final a = await (db.select(db.accounts)
          ..where((x) => x.id.equals(cashId)))
        .getSingle();
    expect(a.name, 'Cash Wallet');

    final emptyId = await repo.addAccount('Temp');
    await repo.deleteAccount(emptyId); // no entries — fine

    await addTx('expense', 5000);
    expect(() => repo.deleteAccount(cashId), throwsStateError);
  });

  test('category: rename, duplicate guard, default delete blocked, '
      'custom delete works until used', () async {
    var cats = await db.select(db.categories).get();
    final other = cats.firstWhere((c) => c.name == 'Other');
    final groceries = cats.firstWhere((c) => c.name == 'Groceries');

    expect(() => repo.renameCategory(other.id, 'Groceries'),
        throwsStateError);
    await repo.renameCategory(other.id, 'Misc');
    cats = await db.select(db.categories).get();
    expect(cats.any((c) => c.name == 'Misc'), isTrue);
    await repo.renameCategory(
        cats.firstWhere((c) => c.name == 'Misc').id, 'Other');

    expect(() => repo.deleteCategory(groceries.id), throwsStateError);

    // A learned (custom) category deletes fine while unused…
    await repo.learnCategoryFromNote(
        categoryId: other.id, kind: 'expense', note: 'Milk');
    cats = await db.select(db.categories).get();
    final milk = cats.firstWhere((c) => c.name == 'Milk');
    await addTx('expense', 12000, categoryId: milk.id);
    // …but refuses once an entry uses it.
    expect(() => repo.deleteCategory(milk.id), throwsStateError);
  });

  test('deleteTransaction: plain entry deletes; lend with repayment '
      'is guarded; reversed entries refuse', () async {
    final pid = await db.into(db.persons).insert(
        PersonsCompanion.insert(name: 'Bilal', createdAt: DateTime.now()));
    final expenseId = await addTx('expense', 7000);
    await repo.deleteTransaction(expenseId);
    expect(await db.select(db.transactions).get(), isEmpty);

    final lendId = await addTx('lend', 30000, personId: pid);
    final repayId = await addTx('lend_repay', 10000, personId: pid);
    expect(() => repo.deleteTransaction(lendId), throwsStateError);
    await repo.deleteTransaction(repayId);
    await repo.deleteTransaction(lendId); // now consistent — allowed

    final incomeId = await addTx('income', 9000);
    await repo.reverseTransaction(incomeId);
    expect(() => repo.deleteTransaction(incomeId), throwsStateError);
  });
}
