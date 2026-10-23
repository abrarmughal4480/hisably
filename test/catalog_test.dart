import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/data/category_catalog.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/repository.dart';
import 'package:hisably/widgets/category_icons.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog covers every seeded category with an icon name', () {
    for (final name in [
      ...CategoryCatalog.expenseNames,
      ...CategoryCatalog.incomeNames,
    ]) {
      expect(CategoryCatalog.iconForName[name], isNotNull,
          reason: '$name has no icon');
      // And every icon name resolves to a real glyph.
      expect(categoryIcon(CategoryCatalog.iconForName[name]),
          isNot(Icons.category_rounded),
          reason: '$name icon name has no glyph');
    }
    expect(CategoryCatalog.renames['Deegar'], 'Other');
    expect(LedgerRepository.categoryRenames, CategoryCatalog.renames);
  });

  test('seed stores icon names; assignCategoryIcons repairs old rows',
      () async {
    final db = HisablyDatabase.forTesting(NativeDatabase.memory());
    final repo = LedgerRepository(db);
    await repo.seedCategoriesIfEmpty();
    var cats = await db.select(db.categories).get();
    expect(cats.firstWhere((c) => c.name == 'Groceries').icon, 'groceries');
    expect(cats.firstWhere((c) => c.name == 'Zakat').icon, 'zakat');
    expect(cats.firstWhere((c) => c.name == 'Salary').icon, 'salary');

    // Simulate an older install whose icons are all the generic default.
    await db.update(db.categories).write(
        const CategoriesCompanion(icon: Value('category')));
    await repo.assignCategoryIcons();
    cats = await db.select(db.categories).get();
    expect(cats.firstWhere((c) => c.name == 'Travel').icon, 'travel');
    expect(cats.every((c) => c.icon != 'category'), isTrue);
    await db.close();
  });

  test('ensureBuiltInCategories adds Family to an old install', () async {
    final db = HisablyDatabase.forTesting(NativeDatabase.memory());
    final repo = LedgerRepository(db);
    await repo.seedCategoriesIfEmpty();
    var cats = await db.select(db.categories).get();
    expect(cats.any((c) => c.name == 'Family'), isTrue);
    // Simulate a pre-Family install, then run the startup ensure.
    await (db.delete(db.categories)
          ..where((tbl) => tbl.name.equals('Family')))
        .go();
    await repo.ensureBuiltInCategories();
    cats = await db.select(db.categories).get();
    expect(cats.where((c) => c.name == 'Family').length, 1);
    expect(cats.firstWhere((c) => c.name == 'Family').icon, 'family');
    await repo.ensureBuiltInCategories(); // idempotent
    cats = await db.select(db.categories).get();
    expect(cats.where((c) => c.name == 'Family').length, 1);
    await db.close();
  });

  test('iconForNote picks fitting icons incl. Roman Urdu', () {
    expect(CategoryCatalog.iconForNote('Milk'), 'milk');
    expect(CategoryCatalog.iconForNote('doodh'), 'milk');
    expect(CategoryCatalog.iconForNote('Roti'), 'bread');
    expect(CategoryCatalog.iconForNote('Cold Drink'), 'juice');
    expect(CategoryCatalog.iconForNote('Ice Cream'), 'icecream');
    expect(CategoryCatalog.iconForNote('Banana'), 'fruit');
    expect(CategoryCatalog.iconForNote('Something Else'), 'label');
    // Every hint value resolves to a real glyph.
    for (final v in CategoryCatalog.noteIconHints.values.toSet()) {
      expect(categoryIcon(v), isNot(Icons.category_rounded), reason: v);
    }
  });

  test('learnCategoryFromNote turns an Other note into a category',
      () async {
    final db = HisablyDatabase.forTesting(NativeDatabase.memory());
    final repo = LedgerRepository(db);
    await repo.seedCategoriesIfEmpty();
    var cats = await db.select(db.categories).get();
    final other = cats.firstWhere((c) => c.name == 'Other');
    await repo.learnCategoryFromNote(
        categoryId: other.id, kind: 'expense', note: 'milk');
    cats = await db.select(db.categories).get();
    final milk = cats.firstWhere((c) => c.name == 'Milk');
    expect(milk.kind, 'expense');
    expect(milk.icon, 'milk');
    expect(milk.isCustom, isTrue);
    // Duplicate in another case is not created twice.
    await repo.learnCategoryFromNote(
        categoryId: other.id, kind: 'expense', note: 'MILK');
    cats = await db.select(db.categories).get();
    expect(cats.where((c) => c.name == 'Milk').length, 1);
    // Long sentence notes never become categories.
    await repo.learnCategoryFromNote(
        categoryId: other.id,
        kind: 'expense',
        note: 'paid 500 for the thing yesterday');
    cats = await db.select(db.categories).get();
    expect(cats.any((c) => c.name.contains('paid')), isFalse);
    // Notes under non-Other categories do nothing.
    final groceries = cats.firstWhere((c) => c.name == 'Groceries');
    await repo.learnCategoryFromNote(
        categoryId: groceries.id, kind: 'expense', note: 'Bread');
    cats = await db.select(db.categories).get();
    expect(cats.any((c) => c.name == 'Bread'), isFalse);
    await db.close();
  });
}
