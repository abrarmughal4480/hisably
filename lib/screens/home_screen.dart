import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import '../widgets/add_account.dart';
import '../widgets/category_icons.dart';
import 'add_transaction_screen.dart';
import 'savings_screen.dart';

/// Home dashboard — approved design, live data from the local database.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final profile = ref.watch(profileProvider);
    final accounts = ref.watch(accountsProvider).value ?? [];
    final txs = ref.watch(transactionsProvider).value ?? [];
    final persons = ref.watch(personsProvider).value ?? [];
    final budgets = ref.watch(budgetsProvider).value ?? [];
    final categories = ref.watch(categoriesProvider).value ?? [];
    // One indexed pass over the ledger (ledger_index module); every
    // aggregate below is then an O(1) map lookup.
    final index = ref.watch(ledgerIndexProvider);

    final now = DateTime.now();
    final totalBalance = index?.totalBalance() ??
        accounts.fold<int>(0, (sum, a) => sum + balanceOf(a, txs));
    final income = index?.monthSum('income', now) ?? monthSum(txs, 'income', now);
    final expense =
        index?.monthSum('expense', now) ?? monthSum(txs, 'expense', now);
    var lenay = 0;
    var denay = 0;
    for (final person in persons) {
      final net = index?.outstandingOf(person.id) ??
          outstandingOf(person.id, txs);
      if (net > 0) {
        lenay += net;
      } else if (net < 0) {
        denay += -net;
      }
    }
    final frequent = index?.frequent() ?? const [];
    final overallBudget =
        budgets.where((b) => b.categoryId == null).firstOrNull;
    final budgetPct = overallBudget != null && overallBudget.limitPaisa > 0
        ? (expense / overallBudget.limitPaisa).clamp(0.0, 1.0)
        : 0.0;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: HisablyColors.accent,
                child: Text(profile?.initials ?? 'H',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.t('greeting'),
                        style: const TextStyle(
                            color: HisablyColors.textSecondary, fontSize: 12)),
                    Text(profile?.name ?? '',
                        style: headingStyle(s.code, size: 16)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [HisablyColors.primary, HisablyColors.primaryDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('totalBalance'),
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text(formatPaisa(totalBalance),
                    style: amountStyle(s.code,
                        size: 30, weight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _BalanceStat(
                        label: s.t('incomeMonth'),
                        value: formatPaisa(income),
                        icon: Icons.arrow_downward_rounded,
                      ),
                    ),
                    Expanded(
                      child: _BalanceStat(
                        label: s.t('expenseMonth'),
                        value: formatPaisa(expense),
                        icon: Icons.arrow_upward_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(s.t('quickActions'), style: headingStyle(s.code, size: 15)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.92,
            mainAxisSpacing: 8,
            crossAxisSpacing: 6,
            children: [
              _QuickTile(
                icon: Icons.arrow_circle_down_rounded,
                label: s.t('income'),
                color: HisablyColors.income,
                onTap: () => _openQuick(context, ref, 'income'),
              ),
              _QuickTile(
                icon: Icons.arrow_circle_up_rounded,
                label: s.t('expense'),
                color: HisablyColors.expense,
                onTap: () => _openQuick(context, ref, 'expense'),
              ),
              _QuickTile(
                icon: Icons.swap_horiz_rounded,
                label: s.t('transfer'),
                color: HisablyColors.transfer,
                onTap: () => _openQuick(context, ref, 'transfer'),
              ),
              _QuickTile(
                icon: Icons.savings_rounded,
                label: s.t('savings'),
                color: HisablyColors.savings,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SavingsScreen())),
              ),
              _QuickTile(
                icon: Icons.north_east_rounded,
                label: s.t('lend'),
                color: HisablyColors.savings,
                onTap: () => _openQuick(context, ref, 'lend'),
              ),
              _QuickTile(
                icon: Icons.south_west_rounded,
                label: s.t('borrow'),
                color: HisablyColors.warning,
                onTap: () => _openQuick(context, ref, 'borrow'),
              ),
              _QuickTile(
                icon: Icons.south_east_rounded,
                label: s.t('repayIn'),
                color: HisablyColors.income,
                onTap: () => _openQuick(context, ref, 'lend_repay'),
              ),
              _QuickTile(
                icon: Icons.north_west_rounded,
                label: s.t('repayOut'),
                color: HisablyColors.expense,
                onTap: () => _openQuick(context, ref, 'borrow_repay'),
              ),
            ],
          ),
          if (frequent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(s.t('frequent'), style: headingStyle(s.code, size: 15)),
            const SizedBox(height: 10),
            SizedBox(
              height: 68,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: frequent.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final combo = frequent[i];
                  final cat = categories
                      .where((c) => c.id == combo.categoryId)
                      .firstOrNull;
                  if (cat == null) return const SizedBox.shrink();
                  final color = combo.type == 'income'
                      ? HisablyColors.income
                      : HisablyColors.expense;
                  return _FrequentCard(
                    icon: categoryIconFor(cat.icon, cat.name),
                    name: cat.name,
                    detail:
                        '${formatPaisa(combo.lastAmountPaisa)} · ${combo.count}×',
                    color: color,
                    onTap: () => _openQuick(context, ref, combo.type,
                        categoryId: combo.categoryId,
                        amountPaisa: combo.lastAmountPaisa),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  title: s.t('lenay'),
                  value: formatPaisa(lenay),
                  color: HisablyColors.income,
                  tint: const Color(0xFF0E2A1A),
                  icon: Icons.arrow_downward_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  title: s.t('denay'),
                  value: formatPaisa(denay),
                  color: HisablyColors.expense,
                  tint: HisablyColors.orangeTint,
                  icon: Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.t('monthlyBudget'),
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        overallBudget == null
                            ? s.t('notSet')
                            : '${formatPaisa(expense)} / ${formatPaisa(overallBudget.limitPaisa)}',
                        style: const TextStyle(
                            color: HisablyColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: budgetPct,
                      minHeight: 10,
                      backgroundColor: HisablyColors.input,
                      valueColor: AlwaysStoppedAnimation(
                          budgetPct >= 1
                              ? HisablyColors.expense
                              : budgetPct >= 0.9
                                  ? HisablyColors.warning
                                  : HisablyColors.accent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    overallBudget == null
                        ? s.t('budgetSetHint')
                        : budgetPct >= 0.9
                            ? s.t('budgetAlmost')
                            : '${(budgetPct * 100).round()}% ${s.t('budgetUsed')}',
                    style: TextStyle(
                        color: budgetPct >= 0.9
                            ? HisablyColors.warning
                            : HisablyColors.textSecondary,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.t('accounts'),
                            style: headingStyle(s.code, size: 15)),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => showAddAccountDialog(context, ref),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: Text(s.t('add')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: HisablyColors.text,
                          backgroundColor: HisablyColors.input,
                          side: const BorderSide(color: HisablyColors.border),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: const Size(0, 34),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (accounts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(s.t('noAccountsYet'),
                          style: const TextStyle(
                              color: HisablyColors.textSecondary,
                              fontSize: 13)),
                    )
                  else
                    for (final a in accounts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(child: Text(a.name)),
                            Text(
                                formatPaisa(
                                    index?.balanceOf(a.id) ?? balanceOf(a, txs)),
                                style: amountStyle(s.code, size: 15)),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick Actions / Frequent taps open the Add screen pre-filled. With
/// no account yet, the first step is adding one (same rule as the
/// shell's + button).
Future<void> _openQuick(BuildContext context, WidgetRef ref, String type,
    {int? categoryId, int? amountPaisa}) async {
  final accounts = ref.read(accountsProvider).value ?? [];
  if (accounts.isEmpty) {
    final added = await showAddAccountDialog(context, ref);
    if (!added || !context.mounted) return;
  }
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AddTransactionScreen(
        presetType: type,
        presetCategoryId: categoryId,
        presetAmountPaisa: amountPaisa,
      ),
    ),
  );
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _FrequentCard extends StatelessWidget {
  const _FrequentCard({
    required this.icon,
    required this.name,
    required this.detail,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String name;
  final String detail;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: HisablyColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HisablyColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: color.withValues(alpha: 0.13),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(detail,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: HisablyColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  const _BalanceStat(
      {required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Colors.white24,
          child: Icon(icon, size: 15, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.title,
      required this.value,
      required this.color,
      required this.tint,
      required this.icon});
  final String title;
  final String value;
  final Color color;
  final Color tint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: tint,
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 10),
            Text(title,
                style: const TextStyle(
                    color: HisablyColors.textSecondary, fontSize: 12)),
            Text(value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
