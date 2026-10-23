import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/auto_backup.dart';
import '../data/backup_service.dart';
import '../data/google_auth.dart';
import '../data/providers.dart';
import '../data/repository.dart';
import '../data/universal_import.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import '../widgets/drive_backup_feedback.dart';

/// Universal Import (user feature, build 2020): bring data from
/// another app or a bank into Hisably.
///
/// Flow: pick a CSV/JSON file → the engine guesses which column is
/// the date, the amount, etc. → the user checks/fixes the mapping
/// → a preview (counts + totals + sample rows) → one safe import
/// (a safety backup of current data is written first; unknown
/// categories and accounts are created on the fly).
class UniversalImportScreen extends ConsumerStatefulWidget {
  const UniversalImportScreen({super.key, this.initialTable});

  /// When the smart Import entry already picked and parsed the
  /// file, it arrives here ready to map — no second file pick.
  final ImportTable? initialTable;

  @override
  ConsumerState<UniversalImportScreen> createState() =>
      _UniversalImportScreenState();
}

class _UniversalImportScreenState
    extends ConsumerState<UniversalImportScreen> {
  ImportTable? _table;
  Map<ImportField, int?> _mapping = {};
  ImportParseResult? _preview;
  int? _targetAccountId;
  bool _busy = false;
  ({int imported, int categoriesCreated, int accountsCreated})? _result;

  static const _fieldLabels = <ImportField, String>{
    ImportField.date: 'fieldDate',
    ImportField.amount: 'fieldAmount',
    ImportField.debit: 'fieldDebit',
    ImportField.credit: 'fieldCredit',
    ImportField.type: 'fieldType',
    ImportField.category: 'fieldCategory',
    ImportField.note: 'fieldNote',
    ImportField.account: 'fieldAccount',
  };

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTable;
    if (initial != null) {
      _table = initial;
      _mapping = guessColumns(initial.headers);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
    }
  }

  Future<void> _pick() async {
    final s = ref.read(stringsProvider);
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || picked.single.path == null) return;
    final text = await File(picked.single.path!).readAsString();
    final trimmed = text.trimLeft();
    ImportTable? table;
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      table = tableFromJson(text);
    }
    table ??= parseDelimited(text);
    if (table.headers.isEmpty || table.rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('fileUnreadable'))));
      }
      return;
    }
    setState(() {
      _table = table;
      _mapping = guessColumns(table!.headers);
      _preview = null;
    });
  }

  bool get _mappingValid {
    final m = _mapping;
    return m[ImportField.date] != null &&
        (m[ImportField.amount] != null ||
            m[ImportField.debit] != null ||
            m[ImportField.credit] != null);
  }

  void _makePreview() {
    final s = ref.read(stringsProvider);
    if (!_mappingValid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('needDateAmount'))));
      return;
    }
    setState(() => _preview = buildEntries(_table!, _mapping));
  }

  Future<void> _doImport() async {
    final preview = _preview;
    if (preview == null || preview.entries.isEmpty) return;
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      // Safety first: a restorable copy of the current data.
      await BackupService(db).exportToFile();
      final fallback = _targetAccountId ??
          ref.read(accountsProvider).value?.firstOrNull?.id ??
          1;
      final result = await ref
          .read(repositoryProvider)
          .importParsedEntries(preview.entries, fallbackAccountId: fallback);
      if (mounted) setState(() => _result = result);
      // Imported data is backed up to Drive right away, with
      // visible progress (user request, 23 Oct 2026).
      await backupToDriveWithFeedback(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('importTitle'))),
      body: _result != null
          ? _doneView(s)
          : _preview != null
              ? _previewView(s)
              : _table != null
                  ? _mappingView(s)
                  : _emptyView(s),
    );
  }

  Widget _emptyView(S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.upload_file_rounded,
                size: 56, color: HisablyColors.accent),
            const SizedBox(height: 16),
            Text(s.t('importOtherSub'), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: Text(s.t('importFile')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mappingView(S s) {
    final table = _table!;
    final accounts = ref.watch(accountsProvider).value ?? const [];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(s.t('mapColumns'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(s.t('mapColumnsSub'),
            style: const TextStyle(color: HisablyColors.textSecondary)),
        const SizedBox(height: 16),
        for (final field in ImportField.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text(s.t(_fieldLabels[field]!))),
                Expanded(
                  flex: 6,
                  child: DropdownButton<int?>(
                    isExpanded: true,
                    value: _mapping[field],
                    items: [
                      DropdownMenuItem<int?>(
                          value: null, child: Text(s.t('colNone'))),
                      for (var i = 0; i < table.headers.length; i++)
                        DropdownMenuItem<int?>(
                            value: i,
                            child: Text(table.headers[i],
                                overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() {
                      _mapping = {..._mapping, field: v};
                    }),
                  ),
                ),
              ],
            ),
          ),
        if (_mapping[ImportField.account] == null && accounts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(s.t('targetAccount'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          DropdownButton<int>(
            isExpanded: true,
            value: _targetAccountId ?? accounts.first.id,
            items: [
              for (final a in accounts)
                DropdownMenuItem<int>(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _targetAccountId = v),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _makePreview,
          icon: const Icon(Icons.visibility_rounded, size: 18),
          label: Text(s.t('previewImport')),
        ),
      ],
    );
  }

  Widget _previewView(S s) {
    final preview = _preview!;
    final fmt = DateFormat('d MMM yyyy');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
            '${preview.entries.length} ${s.t('entriesReady')} • ${preview.skipped} ${s.t('entriesSkipped')}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text(
            '${s.t('totalIn')}: ${formatPaisa(preview.totalInPaisa)}   •   ${s.t('totalOut')}: ${formatPaisa(preview.totalOutPaisa)}'),
        const Divider(height: 28),
        for (final e in preview.entries.take(8))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                e.isIncome
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: e.isIncome ? Colors.green : Colors.redAccent,
                size: 18),
            title: Text(
                e.note.isNotEmpty
                    ? e.note
                    : (e.category.isNotEmpty ? e.category : '—'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${fmt.format(e.date)}${e.category.isNotEmpty ? ' • ${e.category}' : ''}'),
            trailing: Text(formatPaisa(e.amountPaisa),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        if (preview.entries.length > 8)
          Text('… +${preview.entries.length - 8}',
              style: const TextStyle(color: HisablyColors.textSecondary)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy || preview.entries.isEmpty ? null : _doImport,
          icon: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_done_rounded, size: 18),
          label: Text(s.t('importNow')),
        ),
        TextButton(
          onPressed: () => setState(() => _preview = null),
          child: Text(s.t('mapColumns')),
        ),
      ],
    );
  }

  Widget _doneView(S s) {
    final r = _result!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text(s.t('importingDone'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
                '${r.imported} ${s.t('entriesReady')}\n${r.categoriesCreated} ${s.t('fieldCategory')} • ${r.accountsCreated} ${s.t('fieldAccount')}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: HisablyColors.textSecondary)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.t('doneBtn')),
            ),
          ],
        ),
      ),
    );
  }
}
