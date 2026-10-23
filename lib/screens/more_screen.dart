import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup_service.dart';
import '../l10n/strings.dart';
import '../widgets/google_account_card.dart';
import '../widgets/smart_import.dart';
import '../theme/hisably_theme.dart';
import '../widgets/logo.dart';
import 'package:local_auth/local_auth.dart';

import '../data/pin_service.dart';
import '../data/providers.dart';
import 'budget_screen.dart';
import 'categories_screen.dart';
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
          const GoogleAccountCard(),
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
                  leading: const Icon(Icons.category_rounded),
                  title: Text(s.t('categories')),
                  subtitle: Text(s.t('categoriesSub')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const CategoriesScreen())),
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
                  leading: const Icon(Icons.file_download_rounded),
                  title: Text(s.t('importTitle')),
                  subtitle: Text(s.t('importSmartSub')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => startSmartImport(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_rounded),
                  title: Text(s.t('appPin')),
                  subtitle: Text(s.t('appPinSub')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pinFlow(context, ref),
                ),
                const Divider(height: 1),
                const _FingerprintTile(),
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

/// Fingerprint unlock switch (user request, 23 Oct 2026): the
/// setting must be visible and changeable in the app, not only
/// asked once during setup. Shown only when a PIN exists and the
/// device actually has biometrics.
class _FingerprintTile extends ConsumerStatefulWidget {
  const _FingerprintTile();

  @override
  ConsumerState<_FingerprintTile> createState() =>
      _FingerprintTileState();
}

class _FingerprintTileState extends ConsumerState<_FingerprintTile> {
  bool? _enabled;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var available = false;
    try {
      final auth = LocalAuthentication();
      final enrolled = await auth.getAvailableBiometrics().timeout(
          const Duration(seconds: 4),
          onTimeout: () => const <BiometricType>[]);
      available = enrolled.isNotEmpty ||
          (await auth.canCheckBiometrics && await auth.isDeviceSupported());
    } catch (_) {}
    final pinSet = await PinService().isPinSet();
    final enabled = await BiometricSetting.isEnabled();
    if (mounted) {
      setState(() {
        _visible = available && pinSet;
        _enabled = enabled;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      // Prove it works before switching it on.
      var ok = false;
      try {
        ok = await LocalAuthentication().authenticate(
          localizedReason: 'Hisably',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
      } catch (_) {}
      if (!ok) return;
    }
    await BiometricSetting.setEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    return ListTile(
      leading: const Icon(Icons.fingerprint_rounded),
      title: Text(s.t('fingerprintUnlock')),
      trailing: _enabled == null
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Switch(value: _enabled!, onChanged: _toggle),
    );
  }
}
