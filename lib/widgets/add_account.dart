import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';

/// Popular Pakistani banks & wallets offered when adding an account.
/// The user picks one or types a custom name — nothing is pre-added.
const bankSuggestions = <String>[
  'Cash',
  'HBL',
  'Meezan Bank',
  'UBL',
  'MCB',
  'Allied Bank',
  'Bank Alfalah',
  'National Bank',
  'JazzCash',
  'EasyPaisa',
  'NayaPay',
  'SadaPay',
  'Savings',
];

/// Shows the Add Account dialog. Returns true if an account was added.
Future<bool> showAddAccountDialog(BuildContext context, WidgetRef ref) async {
  final s = ref.read(stringsProvider);
  final accounts = ref.read(accountsProvider).value ?? [];
  final existingNames = accounts.map((a) => a.name.toLowerCase()).toSet();
  final suggestions =
      bankSuggestions.where((n) => !existingNames.contains(n.toLowerCase())).toList();
  final ctrl = TextEditingController();

  Future<bool> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (existingNames.contains(trimmed.toLowerCase())) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('accountExists'))));
      return false;
    }
    await ref.read(repositoryProvider).addAccount(trimmed);
    return true;
  }

  final added = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.t('addAccount'), style: headingStyle(s.code, size: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in suggestions)
                  ActionChip(
                    label: Text(name),
                    backgroundColor: HisablyColors.input,
                    side: const BorderSide(color: HisablyColors.border),
                    onPressed: () async {
                      final ok = await add(name);
                      if (ok && context.mounted) Navigator.pop(context, true);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(s.t('pickAccountHint'),
                style: const TextStyle(
                    color: HisablyColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: s.t('accountName')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: () async {
            final ok = await add(ctrl.text);
            if (ok && context.mounted) Navigator.pop(context, true);
          },
          child: Text(s.t('add')),
        ),
      ],
    ),
  );
  return added ?? false;
}
