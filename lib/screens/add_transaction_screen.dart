import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import '../widgets/amount_keypad.dart';
import '../widgets/category_icons.dart';
import '../widgets/hisably_dropdown.dart';

class _TypeOption {
  const _TypeOption(this.type, this.label, this.color);
  final String type;
  final String label;
  final Color color;
}

const _types = [
  _TypeOption('expense', 'expense', HisablyColors.expense),
  _TypeOption('income', 'income', HisablyColors.income),
  _TypeOption('lend', 'lend', HisablyColors.savings),
  _TypeOption('borrow', 'borrow', HisablyColors.warning),
  _TypeOption('lend_repay', 'repayIn', HisablyColors.income),
  _TypeOption('borrow_repay', 'repayOut', HisablyColors.expense),
  _TypeOption('transfer', 'transfer', HisablyColors.transfer),
];

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen(
      {super.key,
      this.editing,
      this.presetType,
      this.presetPersonId,
      this.presetCategoryId,
      this.presetAmountPaisa});

  /// When set, the form edits this entry in place (v0.6.4) instead of
  /// adding a new one.
  final Transaction? editing;

  /// Pre-selected values for quick actions and dashboard shortcuts
  /// (v0.6.6+): "Return Money" from a person's Khata page, Quick
  /// Actions and Frequent repeats from Home.
  final String? presetType;
  final int? presetPersonId;
  final int? presetCategoryId;
  final int? presetAmountPaisa;

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  String _type = 'expense';
  String _amountText = '';
  final _noteCtrl = TextEditingController();
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  int? _personId;
  bool _saving = false;

  /// When the entry happened. Defaults to now; the user can pick any
  /// past date/time so backdated entries order correctly (v0.6.9).
  late DateTime _occurredAt;

  bool get _isEdit => widget.editing != null;
  bool get _isKhata =>
      const {'lend', 'borrow', 'lend_repay', 'borrow_repay'}.contains(_type);
  bool get _isSavingType => _type == 'saving' || _type == 'saving_withdraw';
  bool get _isCategorised => _type == 'income' || _type == 'expense';

  /// Khata and savings entries keep their type (and person/goal) when
  /// edited — changing those would rewrite someone else's ledger.
  /// Account, amount, category and note stay editable: the exact fix
  /// for "I picked Cash instead of JazzCash".
  bool get _typeLocked =>
      _isEdit && (_isKhata || _isSavingType || widget.editing!.personId != null);

  @override
  void initState() {
    super.initState();
    _occurredAt = widget.editing?.occurredAt ?? DateTime.now();
    if (widget.presetType != null) _type = widget.presetType!;
    if (widget.presetPersonId != null) _personId = widget.presetPersonId;
    if (widget.presetCategoryId != null) {
      _categoryId = widget.presetCategoryId;
    }
    if (widget.presetAmountPaisa != null) {
      final rupees = widget.presetAmountPaisa! / 100;
      _amountText = rupees == rupees.truncateToDouble()
          ? rupees.toInt().toString()
          : rupees.toStringAsFixed(2);
    }
    final e = widget.editing;
    if (e != null) {
      _type = e.type;
      final rupees = e.amountPaisa / 100;
      _amountText = rupees == rupees.truncateToDouble()
          ? rupees.toInt().toString()
          : rupees.toStringAsFixed(2);
      _noteCtrl.text = e.note;
      _accountId = e.accountId;
      _toAccountId = e.toAccountId;
      _categoryId = e.categoryId;
      _personId = e.personId;
    }
  }

  Future<void> _addPerson() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ref.read(stringsProvider).t('newPerson')),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(labelText: ref.read(stringsProvider).t('name')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ref.read(stringsProvider).t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
              child: Text(ref.read(stringsProvider).t('add'))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final db = ref.read(databaseProvider);
    final id = await db.into(db.persons).insert(PersonsCompanion.insert(
          name: name,
          createdAt: DateTime.now(),
        ));
    setState(() => _personId = id);
  }

  /// On-screen keypad input: digits, one decimal point (max 2 places),
  /// backspace. Keeps the amount a clean, always-valid string.
  void _onAmountKey(String key) {
    setState(() {
      if (key == 'back') {
        if (_amountText.isNotEmpty) {
          _amountText = _amountText.substring(0, _amountText.length - 1);
        }
      } else if (key == '.') {
        if (!_amountText.contains('.')) {
          _amountText = _amountText.isEmpty ? '0.' : '$_amountText.';
        }
      } else {
        if (_amountText.contains('.') &&
            _amountText.split('.')[1].length >= 2) {
          return;
        }
        if (_amountText.replaceAll('.', '').length >= 10) return;
        _amountText = _amountText == '0' ? key : '$_amountText$key';
      }
    });
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _occurredAt = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String _fmtDateTime(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    var h = d.hour % 12;
    if (h == 0) h = 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final mm = d.minute.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year} · $h:$mm $ampm';
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    final rupees = double.tryParse(_amountText.trim());
    if (rupees == null || rupees <= 0) {
      _snack(s.t('enterValidAmount'));
      return;
    }
    if (_accountId == null) {
      _snack(s.t('chooseAccount'));
      return;
    }
    if (_type == 'transfer' && (_toAccountId == null || _toAccountId == _accountId)) {
      _snack(s.t('chooseToAccount'));
      return;
    }
    if (_isKhata && _personId == null) {
      _snack(s.t('choosePerson'));
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(repositoryProvider);
      if (_isEdit) {
        await repo.updateTransaction(
          id: widget.editing!.id,
          type: _type,
          amountPaisa: (rupees * 100).round(),
          accountId: _accountId!,
          toAccountId: _type == 'transfer' ? _toAccountId : null,
          categoryId: _isCategorised ? _categoryId : null,
          personId: _isKhata ? _personId : null,
          savingsGoalId:
              _isSavingType ? widget.editing!.savingsGoalId : null,
          note: _noteCtrl.text.trim(),
          occurredAt: _occurredAt,
        );
      } else {
        await repo.addTransaction(
          TransactionsCompanion.insert(
            type: _type,
            amountPaisa: (rupees * 100).round(),
            accountId: _accountId!,
            toAccountId: Value(_type == 'transfer' ? _toAccountId : null),
            categoryId: Value(_isCategorised ? _categoryId : null),
            personId: Value(_isKhata ? _personId : null),
            note: Value(_noteCtrl.text.trim()),
            occurredAt: _occurredAt,
            createdAt: DateTime.now(),
          ),
        );
        // A short note under Other becomes a category of its own
        // for next time (with an auto-picked icon).
        if (_isCategorised) {
          await repo.learnCategoryFromNote(
            categoryId: _categoryId,
            kind: _type,
            note: _noteCtrl.text,
          );
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack(e.toString().replaceFirst(RegExp(r'^(StateError|Bad state):?\s*'), ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final accounts = ref.watch(accountsProvider).value ?? [];
    final categories = ref.watch(categoriesProvider).value ?? [];
    final persons = ref.watch(personsProvider).value ?? [];
    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }
    final kindCats = categories
        .where((c) => !_isCategorised || c.kind == _type || c.kind == 'both')
        .toList();

    return Scaffold(
      appBar: AppBar(
          title: Text(s.t(_isEdit ? 'editTransaction' : 'addTransaction'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (_isSavingType)
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.savings_rounded, size: 18),
                label: Text(s.t(_type == 'saving' ? 'addMoney' : 'withdraw')),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _types)
                  ChoiceChip(
                    label: Text(s.t(t.label)),
                    selected: _type == t.type,
                    onSelected: _typeLocked
                        ? null
                        : (_) => setState(() {
                              _type = t.type;
                              _categoryId = null;
                            }),
                  ),
              ],
            ),
          const SizedBox(height: 20),
          Text(s.t('amount'),
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: HisablyColors.input,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HisablyColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Rs ',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: HisablyColors.textSecondary)),
                Text(
                  _amountText.isEmpty ? '0' : _amountText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: _amountText.isEmpty
                        ? HisablyColors.textTertiary
                        : HisablyColors.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // The numerical keypad sits directly under the amount field
          // (user request, v0.6.9) — always visible, no scrolling.
          AmountKeypad(onKey: _onAmountKey),
          const SizedBox(height: 16),
          HisablyDropdown<int>(
            label: _type == 'transfer' ? 'From account' : 'Account',
            value: _accountId,
            items: [
              for (final a in accounts)
                HisablyDropdownItem(value: a.id, label: a.name),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          if (_type == 'transfer') ...[
            const SizedBox(height: 16),
            HisablyDropdown<int>(
              label: s.t('toAccount'),
              value: _toAccountId,
              items: [
                for (final a in accounts)
                  HisablyDropdownItem(value: a.id, label: a.name),
              ],
              onChanged: (v) => setState(() => _toAccountId = v),
            ),
          ],
          if (_isCategorised) ...[
            const SizedBox(height: 16),
            HisablyDropdown<int>(
              label: s.t('category'),
              value: _categoryId,
              items: [
                for (final c in kindCats)
                  HisablyDropdownItem(
                      value: c.id,
                      label: c.name,
                      icon: categoryIconFor(c.icon, c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ],
          if (_isKhata) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: HisablyDropdown<int>(
                    label: s.t('person'),
                    value: _personId,
                    enabled: !_isEdit,
                    items: [
                      for (final p in persons)
                        HisablyDropdownItem(value: p.id, label: p.name),
                    ],
                    onChanged: (v) => setState(() => _personId = v),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: IconButton.filledTonal(
                    onPressed: _addPerson,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(s.t('date'),
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickDateTime,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: HisablyColors.input,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HisablyColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded,
                      size: 20, color: HisablyColors.textSecondary),
                  const SizedBox(width: 10),
                  Text(_fmtDateTime(_occurredAt),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: s.t('noteOptional'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: HisablyColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: Text(
                _saving
                    ? 'Saving...'
                    : (_isEdit ? s.t('saveChanges') : 'Save Transaction'),
                style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
