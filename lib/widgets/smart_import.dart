import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup_service.dart';
import '../data/providers.dart';
import '../data/universal_import.dart';
import '../l10n/strings.dart';
import '../screens/universal_import_screen.dart';
import 'drive_backup_feedback.dart';

/// The one smart Import entry (user UX rule, 23 Oct 2026): a
/// single button, a plain label, and the app figures out the rest.
///
/// The user picks ONE file:
/// * a Hisably backup → preview + confirm + restore (current data
///   is replaced; a safety copy is saved first);
/// * anything else readable (another app's or a bank's CSV/JSON) →
///   the column-mapping import screen, with the file already
///   loaded;
/// * anything else → a clear "couldn't read this file" message.
Future<void> startSmartImport(BuildContext context, WidgetRef ref) async {
  final s = ref.read(stringsProvider);
  final picked = await FilePicker.pickFiles();
  if (picked.isEmpty || picked.single.path == null) return;
  final text = await File(picked.single.path!).readAsString();
  if (!context.mounted) return;

  if (_isHisablyBackup(text)) {
    await _restoreHisablyBackup(context, ref, text);
    return;
  }
  final trimmed = text.trimLeft();
  ImportTable? table;
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    table = tableFromJson(text);
  }
  table ??= parseDelimited(text);
  if (table.headers.isEmpty || table.rows.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.t('fileUnreadable'))));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UniversalImportScreen(initialTable: table)));
}

bool _isHisablyBackup(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is Map && decoded['app'] == 'Hisably';
  } catch (_) {
    return false;
  }
}

Future<void> _restoreHisablyBackup(
    BuildContext context, WidgetRef ref, String text) async {
  final s = ref.read(stringsProvider);
  final service = BackupService(ref.read(databaseProvider));
  Map<String, int> summary;
  try {
    summary = service.preview(text);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${s.t('invalidBackup')}: $e')));
    }
    return;
  }
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.t('restoreTitle')),
      content: Text('${summary['accounts']} ${s.t('accounts')} • '
          '${summary['transactions']} ${s.t('transactions')}\n\n'
          '${s.t('firstImportBody')}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.t('cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.t('restore'))),
      ],
    ),
  );
  if (ok != true) return;
  await service.restoreFromJson(text);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(s.t('restoreDone'))));
  // A restored file becomes the live data — back it up to Drive
  // right away, with visible progress (user request, 23 Oct).
  await backupToDriveWithFeedback(context, ref);
}
