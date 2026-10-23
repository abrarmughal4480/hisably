import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/auto_backup.dart';
import '../data/backup_service.dart';
import '../data/drive_backup.dart';
import '../data/google_auth.dart';
import '../data/profile.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'drive_backup_feedback.dart';

/// Data synchronisation right after a Google sign-in (user
/// rules, 23 Oct 2026 — standard account behaviour):
///
/// * the account has no backup yet → this device's data is
///   uploaded as the first backup;
/// * this device is empty and the account has a backup → the
///   data is fetched back automatically;
/// * BOTH sides hold data → the user is asked which data to
///   keep (the account's or this device's), and the choice is
///   confirmed a second time before anything is replaced.
///   Nothing is ever overwritten silently.
Future<void> syncDataAfterSignIn(
    BuildContext context, WidgetRef ref) async {
  final s = ref.read(stringsProvider);
  await AutoBackup.clearSignedOutLatch();
  final auth = ref.read(googleAuthProvider);
  final db = ref.read(databaseProvider);
  // Establish the session on this instance first: the sync must
  // never depend on a silent restore happening somewhere else
  // first (root cause of the 00-after-login bug, 23 Oct 2026).
  final sessionUser = auth.currentUser ?? await auth.signInSilently();
  if (sessionUser == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('syncDriveUnreachable'))));
    }
    return;
  }
  final drive = DriveBackup(auth);

  ({String id, DateTime modified})? info;
  try {
    info = await drive.findBackup();
  } catch (_) {
    // Never fail silently (user rule, 23 Oct 2026): the user must
    // always be told what happened to their data.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('syncDriveUnreachable'))));
    }
    return;
  }
  final localCount = (await db.select(db.transactions).get()).length;
  final decision = AutoBackup.decideSync(
      driveHasBackup: info != null, localTransactions: localCount);
  if (decision == SyncDecision.uploadFirst) {
    await backupToDriveWithFeedback(context, ref);
    return;
  }

  String? json;
  try {
    json = await drive.downloadBackup();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('syncDriveUnreachable'))));
    }
    return;
  }
  if (json == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('syncNoBackup'))));
    }
    return;
  }
  final jsonData = json;

  if (decision == SyncDecision.autoRestore) {
    // Empty device: fetch the account's data automatically — and
    // SAY what came back (user rule, 23 Oct 2026). An empty backup
    // restoring "successfully" is exactly how lost data stayed
    // invisible: the outcome is now always reported with counts.
    Map<String, int> counts;
    try {
      counts = BackupService(db).preview(jsonData);
    } catch (_) {
      counts = const {};
    }
    if ((counts['transactions'] ?? 0) == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('syncBackupEmpty'))));
      }
      return;
    }
    try {
      if (!context.mounted) return;
      await _restoreWithProgress(
          context, s, () => BackupService(db).restoreFromJson(jsonData));
      ref.read(lastBackupTickProvider.notifier).state++;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${s.t('dataRestored')} '
                '(${counts['transactions']} ${s.t('transactions')})')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('syncRestoreFailed'))));
      }
    }
    return;
  }

  // Both sides hold data — a conflict the user must resolve.
  Map<String, int> summary;
  try {
    summary = BackupService(db).preview(jsonData);
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  final driveDate =
      DateFormat('d MMM yyyy, h:mm a').format(info!.modified.toLocal());
  final choice = await showDialog<int>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(s.t('conflictTitle')),
      content: Text(
          'Google Drive (${s.t('lastBackup')}: $driveDate)\n'
          '${summary['transactions']} ${s.t('transactions')} • '
          '${summary['accounts']} ${s.t('accounts')}\n\n'
          'This device\n'
          '$localCount ${s.t('transactions')}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, null),
            child: Text(s.t('conflictLater'))),
        TextButton(
            onPressed: () => Navigator.pop(c, 2),
            child: Text(s.t('conflictDevice'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, 1),
            child: Text(s.t('conflictAccount'))),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;

  // Double confirmation: the other copy is discarded.
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(s.t('confirmReplaceTitle')),
      content: Text(
          s.t(choice == 1 ? 'confirmReplaceAccount' : 'confirmReplaceDevice')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(s.t('cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(s.t('confirmReplaceBtn'))),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  if (choice == 1) {
    // Keep a restorable safety copy of the device data first.
    await BackupService(db).exportToFile();
    if (!context.mounted) return;
    await _restoreWithProgress(
        context, s, () => BackupService(db).restoreFromJson(jsonData));
    ref.read(lastBackupTickProvider.notifier).state++;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('dataRestored'))));
    }
  } else {
    // The device data wins: it overwrites the Drive backup.
    await backupToDriveWithFeedback(context, ref);
  }
}

/// Runs a Drive restore behind a blocking progress prompt, so a
/// multi-second download/restore never looks like a frozen app.
Future<void> _restoreWithProgress(
    BuildContext context, S s, Future<void> Function() restore) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 18),
        Expanded(child: Text(s.t('fetchingFromDrive'))),
      ]),
    ),
  );
  try {
    await restore();
  } finally {
    if (context.mounted) Navigator.of(context).pop();
  }
}
