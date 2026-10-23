import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import '../widgets/category_icons.dart';
import '../widgets/charts.dart';
import '../widgets/hisably_dropdown.dart';

/// Reports (v0.6.8, full upgrade): period filters (default = last 6
/// months) + account filter, summary tiles, and a set of charts that
/// each answer a real question — Cash Flow (in vs out per month),
/// Balance Trend (where the balance is heading), category Donut
/// (where money went / came from), Daily Spending for short ranges,
/// plus all-time Khata and Savings snapshots. All aggregation runs
/// over the one-pass LedgerIndex — no per-row rescans.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _period = 'last6';
  DateTimeRange? _custom;
  int _accountSel = -1; // -1 = All Accounts
  bool _donutIncome = false;

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month);
  DateTime _addMonths(DateTime d, int n) => DateTime(d.year, d.month + n);

  (DateTime, DateTime) _range(List<Transaction> active) {
    final now = DateTime.now();
    final m0 = _monthStart(now);
    switch (_period) {
      case 'thisMonth':
        return (m0, _addMonths(m0, 1));
      case 'lastMonth':
        return (_addMonths(m0, -1), m0);
      case 'last3':
        return (_addMonths(m0, -2), _addMonths(m0, 1));
      case 'thisYear':
        return (DateTime(now.year), DateTime(now.year + 1));
      case 'allTime':
        if (active.isEmpty) return (m0, _addMonths(m0, 1));
        return (_monthStart(active.first.occurredAt), _addMonths(m0, 1));
      case 'custom':
        final c = _custom;
        if (c != null) {
          return (
            DateTime(c.start.year, c.start.month, c.start.day),
            DateTime(c.end.year, c.end.month, c.end.day + 1),
          );
        }
        return (_addMonths(m0, -5), _addMonths(m0, 1));
      default: // last6
        return (_addMonths(m0, -5), _addMonths(m0, 1));
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _custom ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 29)), end: now),
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _period = 'custom';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final txs = ref.watch(transactionsProvider).value ?? [];
    final accounts = ref.watch(accountsProvider).value ?? [];
    final categories = ref.watch(categoriesProvider).value ?? [];
    final persons = ref.watch(personsProvider).value ?? [];
    final goals = ref.watch(savingsGoalsProvider).value ?? [];
    final index = ref.watch(ledgerIndexProvider);
    final active = index?.active ?? activeTx(txs);

    final accountId = _accountSel == -1 ? null : _accountSel;
    final (start, end) = _range(active);
    final inRange = active
        .where((t) =>
            involvesAccount(t, accountId) &&
            !t.occurredAt.isBefore(start) &&
            t.occurredAt.isBefore(end))
        .toList();

    // Month buckets covering the range.
    final buckets = <DateTime>[];
    var cursor = _monthStart(start);
    final lastBucket = _monthStart(end.subtract(const Duration(days: 1)));
    while (!cursor.isAfter(lastBucket)) {
      buckets.add(cursor);
      cursor = _addMonths(cursor, 1);
    }
    if (buckets.isEmpty) buckets.add(_monthStart(start));

    int sumType(List<Transaction> rows, String type) => rows
        .where((t) => t.type == type)
        .fold(0, (sum, t) => sum + t.amountPaisa);
    final totalIn = sumType(inRange, 'income');
    final totalOut = sumType(inRange, 'expense');
    final net = totalIn - totalOut;
    final savingsRate = totalIn > 0 ? (net / totalIn * 100) : 0.0;
    final nowDay = DateTime.now();
    final tomorrow = DateTime(nowDay.year, nowDay.month, nowDay.day + 1);
    final elapsedEnd = end.isBefore(tomorrow) ? end : tomorrow;
    final elapsedDays = elapsedEnd.difference(start).inDays.clamp(1, 3660);
    final avgPerDay = totalOut ~/ elapsedDays;

    // Cash flow per bucket.
    final flowIn = <int>[], flowOut = <int>[];
    for (final b in buckets) {
      var i = 0, o = 0;
      for (final t in inRange) {
        if (t.occurredAt.year == b.year && t.occurredAt.month == b.month) {
          if (t.type == 'income') i += t.amountPaisa;
          if (t.type == 'expense') o += t.amountPaisa;
        }
      }
      flowIn.add(i);
      flowOut.add(o);
    }
    List<String> bucketLabels() {
      final step = buckets.length > 8 ? (buckets.length / 6).ceil() : 1;
      return [
        for (var i = 0; i < buckets.length; i++)
          (i % step == 0 || i == buckets.length - 1)
              ? DateFormat('MMM').format(buckets[i])
              : '',
      ];
    }

    // Balance trend: opening + everything before the range, then the
    // cumulative balance at each bucket end.
    final opening = accountId != null
        ? (accounts
                .where((a) => a.id == accountId)
                .firstOrNull
                ?.openingPaisa ??
            0)
        : (index?.openingTotal ??
            accounts.fold<int>(0, (sum, a) => sum + a.openingPaisa));
    var running = opening;
    for (final t in active) {
      if (!t.occurredAt.isBefore(start)) break;
      running += deltaForAccount(t, accountId);
    }
    final trendValues = <int>[running];
    final trendLabels = <String>[DateFormat('MMM').format(start)];
    for (final b in buckets) {
      final bEnd = _addMonths(b, 1);
      for (final t in active) {
        if (t.occurredAt.isBefore(b) || !t.occurredAt.isBefore(bEnd)) {
          continue;
        }
        running += deltaForAccount(t, accountId);
      }
      trendValues.add(running);
      trendLabels.add(DateFormat('MMM').format(b));
    }
    if (trendLabels.length > 8) {
      final step = (trendLabels.length / 6).ceil();
      for (var i = 0; i < trendLabels.length; i++) {
        if (i % step != 0 && i != trendLabels.length - 1) trendLabels[i] = '';
      }
    }

    // Category donut (top 6 + Other).
    final donutType = _donutIncome ? 'income' : 'expense';
    final catSums = <int, int>{};
    for (final t in inRange) {
      if (t.type != donutType) continue;
      final key = t.categoryId ?? -1;
      catSums[key] = (catSums[key] ?? 0) + t.amountPaisa;
    }
    final catSorted = catSums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final donutEntries = <(String, int, Category?)>[];
    var otherSum = 0;
    for (var i = 0; i < catSorted.length; i++) {
      final e = catSorted[i];
      final cat = categories.where((c) => c.id == e.key).firstOrNull;
      if (i < 6) {
        donutEntries.add((cat?.name ?? s.t('noCategory'), e.value, cat));
      } else {
        otherSum += e.value;
      }
    }
    if (otherSum > 0) donutEntries.add((s.t('other'), otherSum, null));
    final donutTotal = donutEntries.fold(0, (sum, e) => sum + e.$2);
    const donutPalette = [
      HisablyColors.warning,
      HisablyColors.accent,
      HisablyColors.income,
      HisablyColors.savings,
      HisablyColors.transfer,
      HisablyColors.expense,
      Color(0xFFEC4899),
    ];

    // Daily spending — only meaningful for short ranges.
    final rangeDays = end.difference(start).inDays;
    final showDaily = rangeDays <= 62;
    final dailyValues = <int>[];
    final dailyDays = <int>[];
    if (showDaily) {
      for (var d = start;
          d.isBefore(end);
          d = d.add(const Duration(days: 1))) {
        dailyDays.add(d.day);
        dailyValues.add(inRange
            .where((t) =>
                t.type == 'expense' &&
                t.occurredAt.year == d.year &&
                t.occurredAt.month == d.month &&
                t.occurredAt.day == d.day)
            .fold(0, (sum, t) => sum + t.amountPaisa));
      }
    }

    // Khata + savings snapshots are all-time by design.
    var lenay = 0, denay = 0;
    final personNets = <(Person, int)>[];
    for (final p in persons) {
      final n = index?.outstandingOf(p.id) ?? outstandingOf(p.id, txs);
      if (n > 0) lenay += n;
      if (n < 0) denay += -n;
      if (n != 0) personNets.add((p, n));
    }
    personNets.sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));

    // Period chips: chip label key → internal period value.
    const chips = <(String, String)>[
      ('thisMonth', 'thisMonth'),
      ('lastMonth', 'lastMonth'),
      ('last3Months', 'last3'),
      ('last6Months', 'last6'),
      ('thisYear', 'thisYear'),
      ('allTime', 'allTime'),
      ('custom', 'custom'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(s.t('reports'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (labelKey, value) in chips) ...[
                  ChoiceChip(
                    label: Text(s.t(labelKey)),
                    selected: _period == value,
                    onSelected: (_) {
                      if (value == 'custom') {
                        _pickCustom();
                      } else {
                        setState(() => _period = value);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          HisablyDropdown<int>(
            label: s.t('account'),
            value: _accountSel,
            items: [
              HisablyDropdownItem(value: -1, label: s.t('allAccounts')),
              for (final a in accounts)
                HisablyDropdownItem(value: a.id, label: a.name),
            ],
            onChanged: (v) => setState(() => _accountSel = v ?? -1),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                    title: s.t('totalIncome'),
                    value: formatPaisa(totalIn),
                    color: HisablyColors.income),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                    title: s.t('totalExpense'),
                    value: formatPaisa(totalOut),
                    color: HisablyColors.expense),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                    title: s.t('netLabel'),
                    value: formatPaisa(net),
                    color: net >= 0
                        ? HisablyColors.income
                        : HisablyColors.expense),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                    title: s.t('savingsRate'),
                    value: '${savingsRate.toStringAsFixed(0)}%',
                    color: HisablyColors.savings),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${s.t('avgPerDay')}: ${formatPaisa(avgPerDay)}',
              style: const TextStyle(
                  color: HisablyColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 16),
          if (inRange.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(s.t('noDataPeriod'),
                      style: const TextStyle(
                          color: HisablyColors.textSecondary)),
                ),
              ),
            )
          else ...[
            _SectionCard(
              title: s.t('cashFlow'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      _LegendDot(color: HisablyColors.income, label: 'Income'),
                      SizedBox(width: 16),
                      _LegendDot(
                          color: HisablyColors.expense, label: 'Expense'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 180,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: GroupedBarsPainter(
                        ins: flowIn,
                        outs: flowOut,
                        labels: bucketLabels(),
                        inColor: HisablyColors.income,
                        outColor: HisablyColors.expense,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: s.t('balanceTrend'),
              child: SizedBox(
                height: 170,
                child: CustomPaint(
                  size: Size.infinite,
                  painter:
                      TrendPainter(values: trendValues, labels: trendLabels),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title:
                  _donutIncome ? s.t('whereMoneyCame') : s.t('whereMoneyWent'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ChoiceChip(
                        label: Text(s.t('expense')),
                        selected: !_donutIncome,
                        onSelected: (_) =>
                            setState(() => _donutIncome = false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(s.t('income')),
                        selected: _donutIncome,
                        onSelected: (_) =>
                            setState(() => _donutIncome = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (donutEntries.isEmpty)
                    Text(s.t('noDataPeriod'),
                        style: const TextStyle(
                            color: HisablyColors.textSecondary))
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 138,
                          height: 138,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size(138, 138),
                                painter: DonutPainter(
                                  values: [
                                    for (final e in donutEntries) e.$2
                                  ],
                                  colors: donutPalette,
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      _donutIncome
                                          ? s.t('totalIncome')
                                          : s.t('totalExpense'),
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: HisablyColors.textSecondary)),
                                  Text(formatCompact(donutTotal),
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            children: [
                              for (var i = 0; i < donutEntries.length; i++)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: donutPalette[
                                              i % donutPalette.length],
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (donutEntries[i].$3 != null) ...[
                                        Icon(
                                            categoryIconFor(
                                                donutEntries[i].$3!.icon,
                                                donutEntries[i].$3!.name),
                                            size: 15,
                                            color:
                                                HisablyColors.textSecondary),
                                        const SizedBox(width: 5),
                                      ],
                                      Expanded(
                                        child: Text(donutEntries[i].$1,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                const TextStyle(fontSize: 13)),
                                      ),
                                      Text(
                                        '${formatPaisa(donutEntries[i].$2)} · ${donutTotal > 0 ? (donutEntries[i].$2 / donutTotal * 100).round() : 0}%',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (showDaily) ...[
              const SizedBox(height: 16),
              _SectionCard(
                title: s.t('dailySpending'),
                child: SizedBox(
                  height: 96,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: DailyBarsPainter(
                        values: dailyValues, dayNumbers: dailyDays),
                  ),
                ),
              ),
            ],
          ],
          if (persons.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: s.t('khataSnapshot'),
              child: Column(
                children: [
                  _SnapshotRow(
                      label: s.t('lenay'),
                      value: formatPaisa(lenay),
                      color: HisablyColors.income),
                  _SnapshotRow(
                      label: s.t('denay'),
                      value: formatPaisa(denay),
                      color: HisablyColors.expense),
                  if (personNets.isNotEmpty) const Divider(height: 20),
                  for (final (p, n) in personNets.take(4))
                    _SnapshotRow(
                      label: p.name,
                      value: formatPaisa(n.abs()),
                      color: n > 0
                          ? HisablyColors.income
                          : HisablyColors.expense,
                    ),
                ],
              ),
            ),
          ],
          if (goals.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: s.t('savingsProgress'),
              child: Column(
                children: [
                  for (final g in goals)
                    Builder(builder: (context) {
                      final saved =
                          index?.goalSavedOf(g.id) ?? goalSavedOf(g.id, txs);
                      final hasTarget = g.targetPaisa > 0;
                      final pct = hasTarget
                          ? (saved / g.targetPaisa).clamp(0.0, 1.0)
                          : 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.savings_rounded,
                                    size: 16, color: HisablyColors.savings),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(g.name,
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600)),
                                ),
                                Text(
                                  hasTarget
                                      ? '${formatPaisa(saved)} / ${formatPaisa(g.targetPaisa)}'
                                      : formatPaisa(saved),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: HisablyColors.textSecondary),
                                ),
                              ],
                            ),
                            if (hasTarget) ...[
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: pct.toDouble(),
                                  minHeight: 7,
                                  backgroundColor: HisablyColors.elevated,
                                  color: HisablyColors.savings,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.title, required this.value, required this.color});
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: HisablyColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 5),
            Text(value,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          Text(value,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
