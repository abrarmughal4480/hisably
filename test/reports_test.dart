import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/providers.dart';
import 'package:hisably/screens/reports_screen.dart';
import 'package:hisably/theme/hisably_theme.dart';

Transaction _tx(int id, String type, int paisa,
    {int? categoryId, int? personId, required DateTime at}) {
  return Transaction(
    id: id,
    type: type,
    amountPaisa: paisa,
    accountId: 1,
    categoryId: categoryId,
    personId: personId,
    note: '',
    occurredAt: at,
    createdAt: at,
    isReversed: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports: filters, summary and every chart section render',
      (tester) async {
    // Tall surface so the whole report is built without scrolling.
    tester.view.physicalSize = const Size(1080, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 10);
    final overrides = [
      accountsProvider.overrideWithValue(AsyncData<List<Account>>([
        Account(
            id: 1,
            name: 'Cash',
            type: 'cash',
            openingPaisa: 100000,
            sortOrder: 0,
            isArchived: false),
      ])),
      categoriesProvider.overrideWithValue(AsyncData<List<Category>>([
        Category(
            id: 1,
            name: 'Salary',
            kind: 'income',
            icon: 'salary',
            isCustom: false,
            sortOrder: 0),
        Category(
            id: 2,
            name: 'Groceries',
            kind: 'expense',
            icon: 'groceries',
            isCustom: false,
            sortOrder: 0),
        Category(
            id: 3,
            name: 'Travel',
            kind: 'expense',
            icon: 'travel',
            isCustom: false,
            sortOrder: 1),
      ])),
      personsProvider.overrideWithValue(AsyncData<List<Person>>([
        Person(
            id: 7,
            name: 'Zain',
            phone: '',
            note: '',
            createdAt: thisMonth),
      ])),
      transactionsProvider.overrideWithValue(AsyncData<List<Transaction>>([
        _tx(1, 'income', 200000, categoryId: 1, at: thisMonth),
        _tx(2, 'expense', 50000, categoryId: 2, at: thisMonth),
        _tx(3, 'expense', 15000, categoryId: 3, at: thisMonth),
        _tx(4, 'lend', 20000, personId: 7, at: thisMonth),
      ])),
      budgetsProvider.overrideWithValue(const AsyncData<List<Budget>>([])),
      savingsGoalsProvider
          .overrideWithValue(const AsyncData<List<SavingsGoal>>([])),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: HisablyTheme.app(lang: 'en'),
          home: const ReportsScreen(),
        ),
      ),
    );
    await tester.pump();

    // Default period = last 6 months; summary + charts present.
    expect(find.text('Last 6 Months'), findsOneWidget);
    expect(find.text('Total Income'), findsWidgets);
    expect(find.text('Rs 2,000'), findsOneWidget);
    expect(find.text('Total Expense'), findsWidgets);
    expect(find.text('Cash Flow'), findsOneWidget);
    expect(find.text('Balance Trend'), findsOneWidget);
    expect(find.text('Where the Money Went'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    // All-time Khata snapshot is part of Reports too.
    expect(find.text('Khata Snapshot'), findsOneWidget);
    expect(find.text('Zain'), findsOneWidget);

    // Short range → the daily spending strip appears.
    await tester.tap(find.text('This Month'));
    await tester.pump();
    expect(find.text('Daily Spending'), findsOneWidget);
  });
}
