import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auto_backup.dart';
import '../data/google_auth.dart';
import '../data/profile.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';

/// Backs up to Drive WITH visible feedback (user request,
/// 23 Oct 2026): a "Saving to Google Drive…" prompt while the
/// upload runs, then confirmation that it saved. When no Google
/// account is connected (or its session cannot be restored
/// silently), nothing is shown — there is nothing to save to.
Future<void> backupToDriveWithFeedback(
    BuildContext context, WidgetRef ref) async {
  final auth = ref.read(googleAuthProvider);
  final user = auth.currentUser ?? await auth.signInSilently();
  if (user == null || !context.mounted) return;
  final s = ref.read(stringsProvider);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text(s.t('savingToDrive'))),
        ],
      ),
    ),
  );
  var ok = false;
  try {
    ok = await AutoBackup.run(ref.read(databaseProvider), auth,
        notify: false);
    if (ok) {
      ref.read(profilePhotoTickProvider.notifier).state++;
      ref.read(lastBackupTickProvider.notifier).state++;
    }
  } catch (_) {
    ok = false;
  }
  if (!context.mounted) return;
  Navigator.of(context).pop(); // dismiss the progress prompt
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? s.t('savedToDrive') : s.t('driveSaveFailed'))));
}
