import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/providers.dart';
import 'package:hisably/screens/add_transaction_screen.dart';
import 'package:hisably/theme/hisably_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final overrides = [
    accountsProvider.overrideWithValue(AsyncData<List<Account>>([
      Account(
          id: 1,
          name: 'Cash',
          type: 'cash',
          openingPaisa: 0,
          sortOrder: 0,
          isArchived: false),
    ])),
    categoriesProvider
        .overrideWithValue(const AsyncData<List<Category>>([])),
    personsProvider.overrideWithValue(const AsyncData<List<Person>>([])),
    transactionsProvider
        .overrideWithValue(const AsyncData<List<Transaction>>([])),
    budgetsProvider.overrideWithValue(const AsyncData<List<Budget>>([])),
    savingsGoalsProvider
        .overrideWithValue(const AsyncData<List<SavingsGoal>>([])),
  ];

  Future<void> pumpAdd(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: HisablyTheme.app(lang: 'en'),
          home: const AddTransactionScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('on-screen keypad types the amount; backspace edits it',
      (tester) async {
    await pumpAdd(tester);
    // The keypad is on screen (no system keyboard involved).
    expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.text('0'));
    await tester.pump();
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text('1500'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(find.text('150'), findsOneWidget);
  });

  testWidgets('keypad rules: one decimal point, max two decimals',
      (tester) async {
    await pumpAdd(tester);
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('.'));
    await tester.pump();
    await tester.tap(find.text('.')); // ignored — already has a point
    await tester.pump();
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.text('7'));
    await tester.pump();
    await tester.tap(find.text('9')); // ignored — two decimals already
    await tester.pump();
    expect(find.text('2.57'), findsOneWidget);
  });

  testWidgets('preset amount from a dashboard shortcut is prefilled',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: HisablyTheme.app(lang: 'en'),
          home: const AddTransactionScreen(
              presetType: 'expense', presetAmountPaisa: 45000),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('450'), findsOneWidget);
  });
}
