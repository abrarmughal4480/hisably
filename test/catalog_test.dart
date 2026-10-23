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
}
