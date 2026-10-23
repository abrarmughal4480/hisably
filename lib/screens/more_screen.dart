import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup_service.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import '../widgets/logo.dart';
import '../data/pin_service.dart';
import '../data/providers.dart';
import 'budget_screen.dart';
import 'reports_screen.dart';
import 'savings_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(s.t('more'), style: headingStyle(s.code, size: 20, weight: FontWeight.w800)),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bar_chart_rounded),
                  title: Text(s.t('reports')),
                  subtitle: Text(s.t('reportsSub')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ReportsScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.pie_chart_rounded),
                  title: Text(s.t('budgets')),
                  subtitle: Text(s.t('budgetsSub')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const BudgetScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.savings_rounded),
                  title: Text(s.t('savings')),
                  subtitle: Text(s.t('savingsSub')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SavingsScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: Text(s.t('backupExport')),
                  subtitle: Text(s.t('backupExportSub')),
                  onTap: () => _export(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: Text(s.t('restore')),
                  subtitle: const Text('Replaces current data — a safety '
                      'backup is saved first'),
                  onTap: () => _restore(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_rounded),
                  title: Text(s.t('appPin')),
                  subtitle: Text(s.t('appPinSub')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pinFlow(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const HisablyLogo(size: 54),
                  const SizedBox(height: 10),
                  Text('Hisably',
                      style: amountStyle(s.code, size: 24, weight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(s.t('aboutText'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: HisablyColors.textSecondary,
                          fontSize: 13,
                          height: 1.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final service = BackupService(ref.read(databaseProvider));
    final file = await service.exportToFile();
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], text: 'Hisably backup'));
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked.isEmpty || picked.single.path == null) return;
    final text = await File(picked.single.path!).readAsString();
    final service = BackupService(ref.read(databaseProvider));
    Map<String, int> summary;
    try {
      summary = service.preview(text);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid backup: $e')));
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
            'Contains ${summary['transactions']} transactions, '
            '${summary['persons']} people, ${summary['accounts']} accounts.\n\n'
            'Your current data will be replaced. A safety backup of it is '
            'saved first inside the app folder.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    await service.restoreFromJson(text);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully')));
    }
  }

  Future<void> _pinFlow(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final pin = PinService();
    final pinCtrl = TextEditingController();
    final isSet = await pin.isPinSet();
    if (!context.mounted) return;
    if (!isSet) {
      final newPin = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Set a PIN'),
          content: TextField(
            controller: pinCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            decoration: InputDecoration(labelText: s.t('pinHint')),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, pinCtrl.text.trim()),
                child: Text(s.t('setPin'))),
          ],
        ),
      );
      if (newPin != null && RegExp(r'^\d{4}$').hasMatch(newPin)) {
        await pin.setPin(newPin);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.t('pinSet'))));
        }
      }
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('appPin')),
        content: Text(s.t('pinIsSet')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'remove'),
              child: Text(s.t('removePin'))),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.t('keep'))),
        ],
      ),
    );
    if (action == 'remove') {
      await pin.removePin();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('pinRemoved'))));
      }
    }
  }
}
