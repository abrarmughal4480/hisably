import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/widgets/hisably_dropdown.dart';

void main() {
  testWidgets('custom dropdown opens, shows check on selected, picks a value',
      (tester) async {
    int? picked = 1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => HisablyDropdown<int>(
            label: 'Account',
            value: picked,
            items: const [
              HisablyDropdownItem(value: 1, label: 'Cash'),
              HisablyDropdownItem(value: 2, label: 'JazzCash'),
            ],
            onChanged: (v) => setState(() => picked = v),
          ),
        ),
      ),
    ));
    expect(find.text('Cash'), findsOneWidget);
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    // Popover open: both options visible, selected carries a check.
    expect(find.text('JazzCash'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('JazzCash'));
    await tester.pumpAndSettle();
    expect(picked, 2);
    expect(find.text('JazzCash'), findsOneWidget);
  });
}
