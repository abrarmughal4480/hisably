import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/theme/hisably_theme.dart';
import 'package:hisably/widgets/hisably_dropdown.dart';

void main() {
  testWidgets('dropdown menu opens directly under its field', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: HisablyTheme.app(lang: 'en'),
      home: Scaffold(
        appBar: AppBar(title: const Text('Form')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const SizedBox(height: 300),
            HisablyDropdown<int>(
              label: 'Account',
              value: 1,
              items: const [
                HisablyDropdownItem(value: 1, label: 'Cash'),
                HisablyDropdownItem(value: 2, label: 'JazzCash'),
                HisablyDropdownItem(value: 3, label: 'SadaPay'),
              ],
              onChanged: (_) {},
            ),
            const SizedBox(height: 800),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final triggerRect = tester.getRect(find.text('Cash').first);
    await tester.tap(find.text('Cash').first);
    await tester.pumpAndSettle();

    // The open menu: the item that only exists in the popover.
    final menuItemRect = tester.getRect(find.text('JazzCash'));
    // ignore: avoid_print
    print('TRIGGER: $triggerRect');
    // ignore: avoid_print
    print('MENU ITEM (JazzCash): $menuItemRect');

    expect(menuItemRect.left, closeTo(triggerRect.left, 2));
    // Text-to-text distance: trigger text bottom -> field bottom ~17,
    // gap 6, menu padding 4, first row 44, second row's centred text
    // ~11. Total ~82.
    expect(menuItemRect.top,
        inInclusiveRange(triggerRect.bottom + 68, triggerRect.bottom + 96));
  });
}
