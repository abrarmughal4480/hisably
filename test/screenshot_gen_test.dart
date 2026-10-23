import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/profile.dart';
import 'package:hisably/data/providers.dart';
import 'package:hisably/main.dart';
import 'package:hisably/screens/add_transaction_screen.dart';
import 'package:hisably/screens/khata_person_screen.dart';
import 'package:hisably/screens/reports_screen.dart';
import 'package:hisably/screens/savings_screen.dart';
import 'package:hisably/screens/transactions_screen.dart';
import 'package:hisably/theme/hisably_theme.dart';
import 'package:hisably/widgets/splash_screen.dart';

/// Screenshot factory for the GitHub README — renders the real app
/// with sample data at phone size using the bundled fonts. Run with:
///   flutter test test/screenshot_gen_test.dart --update-goldens
/// Not part of the shipped test suite (excluded from the repo push).
Future<void> _loadFonts() async {
  final families = <String, List<String>>{
    'Sora': ['Sora-600.ttf', 'Sora-700.ttf', 'Sora-800.ttf'],
    'Manrope': ['Manrope-600.ttf', 'Manrope-700.ttf', 'Manrope-800.ttf'],
    'Inter': ['Inter-400.ttf', 'Inter-500.ttf', 'Inter-600.ttf', 'Inter-700.ttf'],
    'NotoNastaliqUrdu': [
      'NotoNastaliqUrdu-400.ttf',
      'NotoNastaliqUrdu-700.ttf'
    ],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
  final roboto = FontLoader('Roboto');
  final robotoBytes = File(
          '/home/hatch/flutter-sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
      .readAsBytesSync();
  roboto.addFont(Future.value(ByteData.view(robotoBytes.buffer)));
  await roboto.load();
  final icons = FontLoader('MaterialIcons');
  final iconBytes = File(
          '/home/hatch/flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
      .readAsBytesSync();
  icons.addFont(Future.value(ByteData.view(iconBytes.buffer)));
  await icons.load();
}

DateTime _daysAgo(int days) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - days, 12, 30);
}

DateTime _monthsAgo(int months, int day) {
  final n = DateTime.now();
  return DateTime(n.year, n.month - months, day, 12, 30);
}

int _id = 100;
Transaction _tx(String type, int paisa,
    {int accountId = 1,
    int? toAccountId,
    int? categoryId,
    int? personId,
    int? savingsGoalId,
    String note = '',
    required DateTime at}) {
  return Transaction(
    id: _id++,
    type: type,
    amountPaisa: paisa,
    accountId: accountId,
    toAccountId: toAccountId,
    categoryId: categoryId,
    personId: personId,
    savingsGoalId: savingsGoalId,
    note: note,
    occurredAt: at,
    createdAt: at,
    isReversed: false,
  );
}

final _accounts = [
  Account(
      id: 1,
      name: 'Cash',
      type: 'cash',
      openingPaisa: 2000000,
      sortOrder: 0,
      isArchived: false),
  Account(
      id: 2,
      name: 'JazzCash',
      type: 'jazzcash',
      openingPaisa: 1000000,
      sortOrder: 1,
      isArchived: false),
];

final _categories = [
  Category(id: 11, name: 'Salary', kind: 'income', icon: 'salary', isCustom: false, sortOrder: 0),
  Category(id: 12, name: 'Freelancing', kind: 'income', icon: 'freelancing', isCustom: false, sortOrder: 1),
  Category(id: 21, name: 'Groceries', kind: 'expense', icon: 'groceries', isCustom: false, sortOrder: 0),
  Category(id: 22, name: 'Travel', kind: 'expense', icon: 'travel', isCustom: false, sortOrder: 1),
  Category(id: 23, name: 'Food & Drink', kind: 'expense', icon: 'food', isCustom: false, sortOrder: 2),
  Category(id: 24, name: 'Electricity', kind: 'expense', icon: 'electricity', isCustom: false, sortOrder: 3),
  Category(id: 25, name: 'Mobile Recharge', kind: 'expense', icon: 'mobile', isCustom: false, sortOrder: 4),
];

final _persons = [
  Person(id: 7, name: 'Zain', phone: '', note: '', createdAt: _daysAgo(30)),
  Person(id: 8, name: 'M. Bilal', phone: '', note: '', createdAt: _daysAgo(28)),
];

List<Transaction> _sampleTxs() {
  _id = 100;
  return [
    _tx('income', 8500000, accountId: 2, categoryId: 11, note: 'October salary', at: _daysAgo(2)),
    _tx('income', 1250000, categoryId: 12, note: 'Client project', at: _daysAgo(5)),
    _tx('expense', 485000, accountId: 2, categoryId: 21, note: 'Monthly rashan', at: _daysAgo(1)),
    _tx('expense', 45000, categoryId: 22, at: _daysAgo(0)),
    _tx('expense', 45000, categoryId: 22, at: _daysAgo(3)),
    _tx('expense', 45000, categoryId: 22, at: _daysAgo(6)),
    _tx('expense', 120000, categoryId: 23, note: 'Dinner', at: _daysAgo(3)),
    _tx('expense', 673000, accountId: 2, categoryId: 24, at: _daysAgo(6)),
    _tx('expense', 60000, categoryId: 25, at: _daysAgo(4)),
    _tx('expense', 60000, categoryId: 25, at: _daysAgo(12)),
    _tx('lend', 500000, personId: 7, at: _daysAgo(8)),
    _tx('lend_repay', 200000, personId: 7, at: _daysAgo(2)),
    _tx('borrow', 10000, personId: 8, at: _daysAgo(9)),
    _tx('saving', 200000, accountId: 2, savingsGoalId: 1, at: _daysAgo(2)),
    _tx('saving', 300000, savingsGoalId: 1, at: _daysAgo(15)),
    // Past months — Reports history.
    for (var m = 1; m <= 5; m++) ...[
      _tx('income', 8500000, accountId: 2, categoryId: 11, at: _monthsAgo(m, 5)),
      _tx('expense', 420000 + m * 15000, accountId: 2, categoryId: 21, at: _monthsAgo(m, 8)),
      _tx('expense', 95000 + m * 8000, categoryId: 23, at: _monthsAgo(m, 11)),
      _tx('expense', 580000 - m * 21000, accountId: 2, categoryId: 24, at: _monthsAgo(m, 14)),
      _tx('expense', 45000, categoryId: 22, at: _monthsAgo(m, 18)),
    ],
  ];
}

List<Override> _overrides(List<Transaction> txs) => [
      accountsProvider.overrideWithValue(AsyncData(_accounts)),
      categoriesProvider.overrideWithValue(AsyncData(_categories)),
      personsProvider.overrideWithValue(AsyncData(_persons)),
      transactionsProvider.overrideWithValue(AsyncData(txs)),
      budgetsProvider.overrideWithValue(AsyncData([
        Budget(id: 1, categoryId: null, limitPaisa: 3000000),
      ])),
      savingsGoalsProvider.overrideWithValue(AsyncData([
        SavingsGoal(
            id: 1,
            name: 'New Phone',
            targetPaisa: 15000000,
            createdAt: _daysAgo(40)),
      ])),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
    Directory('docs/screenshots').createSync(recursive: true);
  });

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('shot: splash', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: HisablyTheme.app(lang: 'en'),
      home: const SplashScreen(tagline: 'Every rupee, accounted for.'),
    ));
    await tester.pump(const Duration(milliseconds: 1250));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../docs/screenshots/01-splash.png'));
  });

  testWidgets('shot: home shell', (tester) async {
    phoneSize(tester);
    SharedPreferences.setMockInitialValues({
      'profile_name': 'Muhammad Abrar',
      'profile_language': 'en',
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(_sampleTxs()),
        child: const HisablyApp(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 2100));
    });
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(find.byType(HisablyApp),
        matchesGoldenFile('../docs/screenshots/02-home.png'));
  });

  testWidgets('shot: add with keypad', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(_sampleTxs()),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: HisablyTheme.app(lang: 'en'),
        home: const AddTransactionScreen(
            presetType: 'expense',
            presetCategoryId: 21,
            presetAmountPaisa: 485000),
      ),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../docs/screenshots/03-add.png'));
  });

  testWidgets('shot: transactions', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(_sampleTxs()),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: HisablyTheme.app(lang: 'en'),
        home: const Scaffold(body: TransactionsScreen()),
      ),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../docs/screenshots/04-transactions.png'));
  });

  testWidgets('shot: khata person', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(_sampleTxs()),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: HisablyTheme.app(lang: 'en'),
        home: KhataPersonScreen(person: _persons[0]),
      ),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../docs/screenshots/05-khata.png'));
  });

  testWidgets('shot: savings', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(_sampleTxs()),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: HisablyTheme.app(lang: 'en'),
        home: const SavingsScreen(),
      ),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../docs/screenshots/06-savings.png'));
  });

  testWidgets('shot: reports', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(_sampleTxs()),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: HisablyTheme.app(lang: 'en'),
        home: const ReportsScreen(),
      ),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../docs/screenshots/07-reports.png'));
  });
}
