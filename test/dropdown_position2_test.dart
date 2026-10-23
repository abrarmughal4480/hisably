import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/theme/hisably_theme.dart';
import 'package:hisably/widgets/hisably_dropdown.dart';

Widget _form({required double spacerBefore, required double spacerAfter}) {
  return MaterialApp(
    theme: HisablyTheme.app(lang: 'en'),
    home: Scaffold(
      appBar: AppBar(title: const Text('Form')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          SizedBox(height: spacerBefore),
          HisablyDropdown<int>(
            label: 'Account',
            value: 1,
            items: const [
              HisablyDropdownItem(value: 1, label: 'Cash'),
              HisablyDropdownItem(value: 2, label: 'JazzCash'),
              HisablyDropdownItem(value: 3, label: 'SadaPay'),
              HisablyDropdownItem(value: 4, label: 'Meezan Bank'),
              HisablyDropdownItem(value: 5, label: 'EasyPaisa'),
            ],
            onChanged: (_) {},
          ),
          SizedBox(height: spacerAfter),
        ],
      ),
    ),
  );
}

Rect _fieldRect(WidgetTester tester) {
  // The trigger box: the Material of the dropdown field. Find via the
  // 'Cash' text inside the (closed) field — use the InkWell ancestor size.
  final textRect = tester.getRect(find.text('Cash').first);
  return Rect.fromLTRB(
      textRect.left - 14, textRect.top - 16, textRect.right + 40, textRect.bottom + 17);
}

void main() {
  testWidgets('flip-up case: field near the bottom of the screen',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_form(spacerBefore: 620, spacerAfter: 40));
    await tester.pumpAndSettle();
    final field = _fieldRect(tester);
    // ignore: avoid_print
    print('FIELD approx: $field (screen 390x844)');
    await tester.tap(find.text('Cash').first);
    await tester.pumpAndSettle();
    final item = tester.getRect(find.text('EasyPaisa'));
    // ignore: avoid_print
    print('LAST ITEM (EasyPaisa): $item');
    // Flipped up: the menu bottom should sit ~6 above the field top,
    // and the last row's text bottom close to it.
    expect(item.left, closeTo(field.left + 14, 4));
    expect(item.bottom, lessThan(field.top));
    expect(field.top - item.bottom, lessThan(60));
  });

  testWidgets('scrolled list: menu follows the field after scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_form(spacerBefore: 500, spacerAfter: 900));
    await tester.pumpAndSettle();
    // Scroll the list up by 250 logical px.
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pumpAndSettle();
    final field = _fieldRect(tester);
    // ignore: avoid_print
    print('FIELD after scroll: $field');
    await tester.tap(find.text('Cash').first);
    await tester.pumpAndSettle();
    final item = tester.getRect(find.text('JazzCash'));
    // ignore: avoid_print
    print('MENU ITEM after scroll: $item');
    expect(item.left, closeTo(field.left + 14, 4));
    expect(item.top, greaterThan(field.bottom));
    expect(item.top - field.bottom, lessThan(80));
  });
}
