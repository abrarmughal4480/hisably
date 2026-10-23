import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/providers.dart';
import 'package:hisably/main.dart';

/// End-to-end flow over a REAL (in-memory) database:
/// shell → + (no accounts) → Add Account dialog → pick HBL →
/// Add Transaction opens → back → Home lists HBL → all tabs render.

/// Waits (real time) until [finder] matches or ~15s pass — robust on
/// slow machines where fixed delays are not enough.
Future<void> untilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full flow: add account, open add-transaction, visit tabs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'profile_name': 'Flow User',
      'profile_language': 'en',
    });
    final db = HisablyDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const HisablyApp(),
      ),
    );
    await untilFound(tester, find.text('Total Balance'));
    expect(find.text('Total Balance'), findsOneWidget);
    expect(find.text('No accounts yet — add your bank or wallet'),
        findsOneWidget);

    // Tap the centre + in the flat bar (27px icon).
    final navAdd = find.byWidgetPredicate((w) =>
        w is Icon && w.icon == Icons.add_rounded && w.size == 27);
    await tester.tap(navAdd);
    await untilFound(tester, find.text('Add Account'));

    // Add Account dialog with bank suggestions.
    expect(find.text('Add Account'), findsOneWidget);
    expect(find.text('HBL'), findsOneWidget);
    expect(find.text('JazzCash'), findsOneWidget);
    await tester.tap(find.text('HBL'));
    await untilFound(tester, find.text('Add Transaction'));
    await tester.pumpAndSettle();

    // Account created → Add Transaction screen opens.
    expect(find.text('Add Transaction'), findsOneWidget);
    await tester.pageBack();
    await untilFound(tester, find.text('Total Balance'));
    await tester.pumpAndSettle();

    // Home accounts card now lists HBL.
    expect(find.text('HBL'), findsWidgets);

    // Transactions tab.
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pump();
    expect(find.textContaining('No transactions yet'), findsOneWidget);

    // Khata tab.
    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pump();
    expect(find.textContaining('khata'), findsWidgets);

    // More tab: budgets, reports, backup and the logo wordmark.
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pump();
    expect(find.text('Budgets'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Hisably'), findsOneWidget);

    // Let the app's 3s startup safety timer fire before disposal.
    await tester.pump(const Duration(seconds: 4));
  });
}
