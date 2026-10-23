import 'package:flutter/material.dart';

import '../theme/hisably_theme.dart';

/// On-screen numeric keypad for amount entry (v0.6.8) — big, calm keys
/// pinned inside the Add/Edit Transaction screen so typing a rupee
/// amount never needs the system keyboard. Keys report '0'..'9', '.'
/// or 'back' through [onKey].
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.onKey});
  final void Function(String key) onKey;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', 'back'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: HisablyColors.secondaryBg,
        border: Border(top: BorderSide(color: HisablyColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in _rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (final key in row)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _Key(
                            label: key,
                            onTap: () => onKey(key),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBack = label == 'back';
    return Material(
      color: HisablyColors.elevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withValues(alpha: 0.08),
        child: SizedBox(
          height: 50,
          child: Center(
            child: isBack
                ? const Icon(Icons.backspace_outlined,
                    size: 22, color: HisablyColors.text)
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: HisablyColors.text,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
