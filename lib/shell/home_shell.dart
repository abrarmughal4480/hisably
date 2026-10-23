import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../screens/add_transaction_screen.dart';
import '../screens/home_screen.dart';
import '../screens/khata_screen.dart';
import '../screens/more_screen.dart';
import '../screens/transactions_screen.dart';
import '../theme/hisably_theme.dart';
import '../widgets/add_account.dart';

/// App shell with the FINAL flat bottom bar (22 Oct 2026):
/// Home, Transactions | + Add | Khata, More — flat on the background,
/// NO labels, NO pill, NO raised button. Active icon is filled,
/// inactive icons are plain outlines.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final repo = ref.read(repositoryProvider);
      await repo.seedCategoriesIfEmpty();
      await repo.migrateCategoryNamesToEnglish();
      await repo.ensureBuiltInCategories();
      await repo.assignCategoryIcons();
    });
  }

  int _index = 0; // 0 Home, 1 Transactions, 2 Khata, 3 More

  static const _pages = [
    HomeScreen(),
    TransactionsScreen(),
    KhataScreen(),
    MoreScreen(),
  ];

  Future<void> _openAdd() async {
    final accounts = ref.read(accountsProvider).value ?? [];
    if (accounts.isEmpty) {
      // No account yet — the user must add their own account first.
      final added = await showAddAccountDialog(context, ref);
      if (!added || !mounted) return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: HisablyColors.background,
          border: Border(top: BorderSide(color: HisablyColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _NavIcon(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  selected: _index == 0,
                  onTap: () => setState(() => _index = 0),
                ),
                _NavIcon(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  selected: _index == 1,
                  onTap: () => setState(() => _index = 1),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _openAdd,
                    child: const SizedBox.expand(
                      child: Icon(Icons.add_rounded,
                          size: 27, color: HisablyColors.textSecondary),
                    ),
                  ),
                ),
                _NavIcon(
                  icon: Icons.menu_book_outlined,
                  activeIcon: Icons.menu_book_rounded,
                  selected: _index == 2,
                  onTap: () => setState(() => _index = 2),
                ),
                _NavIcon(
                  icon: Icons.grid_view_outlined,
                  activeIcon: Icons.grid_view_rounded,
                  selected: _index == 3,
                  onTap: () => setState(() => _index = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox.expand(
          child: Icon(
            selected ? activeIcon : icon,
            size: 25,
            color: selected
                ? HisablyColors.text
                : HisablyColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
