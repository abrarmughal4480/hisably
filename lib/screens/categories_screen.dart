import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import '../widgets/category_icons.dart';

/// Manage categories (user request, 23 Oct 2026): rename any
/// category; delete the ones you created — including the ones the
/// app learned from your notes under Other. Default categories can
/// be renamed but not deleted, and any category that entries still
/// use refuses deletion (the repository explains why).
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final cats = ref.watch(categoriesProvider).value ?? [];
    final expense = cats.where((c) => c.kind == 'expense').toList();
    final income = cats.where((c) => c.kind == 'income').toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('categories'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _header(s.t('expense')),
            for (final c in expense) _row(context, ref, c),
            const SizedBox(height: 18),
            _header(s.t('income')),
            for (final c in income) _row(context, ref, c),
          ],
        ),
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _row(BuildContext context, WidgetRef ref, Category c) {
    final s = ref.read(stringsProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: HisablyColors.primary.withValues(alpha: 0.12),
          child: Icon(categoryIconFor(c.icon, c.name),
              color: HisablyColors.primary, size: 20),
        ),
        title:
            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            Text(c.isCustom ? s.t('customCategory') : s.t('defaultCategory')),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) {
            if (v == 'rename') _rename(context, ref, c);
            if (v == 'delete') _delete(context, ref, c);
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'rename', child: Text(s.t('rename'))),
            PopupMenuItem(
              value: 'delete',
              child: Text(s.t('delete'),
                  style: const TextStyle(color: HisablyColors.expense)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, Category c) async {
    final s = ref.read(stringsProvider);
    final nameCtrl = TextEditingController(text: c.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('rename')),
        content: TextField(
            controller: nameCtrl,
            decoration: InputDecoration(labelText: s.t('name'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('save'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).renameCategory(c.id, nameCtrl.text);
    } catch (e) {
      if (context.mounted) _snack(context, e);
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, Category c) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('deleteCategoryTitle')),
        content: Text(s.t('deleteCategoryBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                  backgroundColor: HisablyColors.expense),
              child: Text(s.t('delete'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).deleteCategory(c.id);
    } catch (e) {
      if (context.mounted) _snack(context, e);
    }
  }

  void _snack(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e
            .toString()
            .replaceFirst(RegExp(r'^(StateError|Bad state):?\s*'), ''))));
  }
}
