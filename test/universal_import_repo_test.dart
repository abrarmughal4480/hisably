import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/repository.dart';
import 'package:hisably/data/universal_import.dart';

/// Repository side of Universal Import (build 2020): parsed entries
/// land in the ledger, unknown categories/accounts are created,
/// empty categories fall back to Other.
void main() {
  late HisablyDatabase db;
  late LedgerRepository repo;
  late int cashId;

  setUp(() async {
    db = HisablyDatabase.forTesting(NativeDatabase.memory());
    repo = LedgerRepository(db);
    await repo.seedCategoriesIfEmpty();
    cashId = await repo.addAccount('Cash');
  });

  tearDown(() async => db.close());

  test('imports entries, creating category + account on the fly', () async {
    final entries = [
      ParsedEntry(
        date: DateTime(2026, 10, 1),
        amountPaisa: 45050,
        isIncome: false,
        category: 'Food',
        note: 'Lunch',
        accountName: '',
      ),
      ParsedEntry(
        date: DateTime(2026, 10, 2),
        amountPaisa: 8500000,
        isIncome: true,
        category: 'Salary',
        note: 'Pay',
        accountName: 'Meezan Bank',
      ),
      ParsedEntry(
        date: DateTime(2026, 10, 3),
        amountPaisa: 10000,
        isIncome: false,
        category: '',
        note: 'Misc',
        accountName: '',
      ),
    ];
    final result =
        await repo.importParsedEntries(entries, fallbackAccountId: cashId);
    expect(result.imported, 3);
    expect(result.accountsCreated, 1); // Meezan Bank
    // Salary is a built-in; "Food" is not (the built-in is called
    // "Food & Drink"), so exactly one category gets created.
    expect(result.categoriesCreated, 1);

    final txs = await db.select(db.transactions).get();
    expect(txs.length, 3);
    final food = txs.firstWhere((t) => t.note == 'Lunch');
    expect(food.type, 'expense');
    expect(food.accountId, cashId);
    final pay = txs.firstWhere((t) => t.note == 'Pay');
    expect(pay.type, 'income');
    expect(pay.accountId, isNot(cashId));
    final misc = txs.firstWhere((t) => t.note == 'Misc');
    final cats = await db.select(db.categories).get();
    final miscCat = cats.firstWhere((c) => c.id == misc.categoryId);
    expect(miscCat.name, 'Other');
  });

  test('a brand-new category name is created once, then reused', () async {
    ParsedEntry e(String note) => ParsedEntry(
          date: DateTime(2026, 10, 1),
          amountPaisa: 5000,
          isIncome: false,
          category: 'Pet Care',
          note: note,
          accountName: '',
        );
    final r1 = await repo.importParsedEntries([e('a'), e('b')],
        fallbackAccountId: cashId);
    expect(r1.categoriesCreated, 1);
    final cats = await db.select(db.categories).get();
    expect(cats.where((c) => c.name == 'Pet Care').length, 1);
  });
}
