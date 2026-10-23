import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/providers.dart';
import 'package:hisably/main.dart';

final _emptyData = [
  accountsProvider.overrideWithValue(const AsyncData<List<Account>>([])),
  categoriesProvider.overrideWithValue(const AsyncData<List<Category>>([])),
  personsProvider.overrideWithValue(const AsyncData<List<Person>>([])),
  transactionsProvider
      .overrideWithValue(const AsyncData<List<Transaction>>([])),
  budgetsProvider.overrideWithValue(const AsyncData<List<Budget>>([])),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shell renders with the flat icon-only bottom bar',
      (tester) async {
    // Tall surface: the dashboard (hero + shortcuts + cards) must fit
    // without the ListView deferring off-screen children.
    tester.view.physicalSize = const Size(1080, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'profile_name': 'Test User',
      'profile_language': 'en',
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(overrides: _emptyData, child: const HisablyApp()),
      );
      // Past the animated splash's minimum display time (1.5 s).
      await Future<void>.delayed(const Duration(milliseconds: 1900));
    });
    await tester.pump();
    // Flat bar: filled/outlined icons, NO text labels.
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsWidgets); // nav + and Accounts + Add
    expect(find.text('Home'), findsNothing);
    expect(find.text('Total Balance'), findsOneWidget);
    // No accounts by default — the empty state invites adding one.
    expect(find.text('No accounts yet — add your bank or wallet'),
        findsOneWidget);
  });

  testWidgets('setup wizard: language step, name step, PIN step',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(overrides: _emptyData, child: const HisablyApp()),
      );
      // Past the animated splash's minimum display time (1.5 s).
      await Future<void>.delayed(const Duration(milliseconds: 1900));
    });
    await tester.pump();
    // Step 1 — choose language (cards, not a toggle).
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('اردو'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    // Step 2 — name.
    expect(find.text('Your full name'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Wizard User');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    // Step 3 — PIN or Skip.
    expect(find.text('App PIN (optional)'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Skip'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    // Registration finished — the shell is up.
    expect(find.text('Total Balance'), findsOneWidget);
    expect(find.text('Wizard User'), findsOneWidget);
  });
}
