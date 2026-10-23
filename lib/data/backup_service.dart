import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import 'database.dart';

/// Versioned JSON backup/restore.
/// Restore is safe: current data is written to a safety backup file first,
/// then all tables are replaced inside one transaction (atomic).
class BackupService {
  BackupService(this.db);
  final HisablyDatabase db;

  static const backupVersion = 1;

  Future<String> exportToJson() async {
    final data = <String, Object?>{
      'app': 'Hisably',
      'backupVersion': backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'accounts': [
        for (final a in await db.select(db.accounts).get())
          {
            'id': a.id,
            'name': a.name,
            'type': a.type,
            'openingPaisa': a.openingPaisa,
            'sortOrder': a.sortOrder,
            'isArchived': a.isArchived,
          }
      ],
      'categories': [
        for (final c in await db.select(db.categories).get())
          {
            'id': c.id,
            'name': c.name,
            'kind': c.kind,
            'icon': c.icon,
            'isCustom': c.isCustom,
            'sortOrder': c.sortOrder,
          }
      ],
      'persons': [
        for (final p in await db.select(db.persons).get())
          {
            'id': p.id,
            'name': p.name,
            'phone': p.phone,
            'note': p.note,
            'createdAt': p.createdAt.toIso8601String(),
          }
      ],
      'transactions': [
        for (final t in await db.select(db.transactions).get())
          {
            'id': t.id,
            'type': t.type,
            'amountPaisa': t.amountPaisa,
            'accountId': t.accountId,
            'toAccountId': t.toAccountId,
            'categoryId': t.categoryId,
            'personId': t.personId,
            'note': t.note,
            'occurredAt': t.occurredAt.toIso8601String(),
            'createdAt': t.createdAt.toIso8601String(),
            'reversesId': t.reversesId,
            'isReversed': t.isReversed,
            'savingsGoalId': t.savingsGoalId,
          }
      ],
      'savings_goals': [
        for (final g in await db.select(db.savingsGoals).get())
          {
            'id': g.id,
            'name': g.name,
            'targetPaisa': g.targetPaisa,
            'createdAt': g.createdAt.toIso8601String(),
          }
      ],
      'budgets': [
        for (final b in await db.select(db.budgets).get())
          {'id': b.id, 'categoryId': b.categoryId, 'limitPaisa': b.limitPaisa}
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<File> exportToFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/hisably-backup-$stamp.json');
    await file.writeAsString(await exportToJson());
    return file;
  }

  /// Validates the file without touching live data. Returns a summary.
  Map<String, int> preview(String jsonText) {
    final data = jsonDecode(jsonText) as Map<String, dynamic>;
    if (data['app'] != 'Hisably' || data['backupVersion'] != backupVersion) {
      throw const FormatException('This is not a Hisably v1 backup');
    }
    return {
      'accounts': (data['accounts'] as List).length,
      'categories': (data['categories'] as List).length,
      'persons': (data['persons'] as List).length,
      'transactions': (data['transactions'] as List).length,
      'budgets': (data['budgets'] as List).length,
      // Older backups have no savings goals — treat as none.
      'savings_goals': (data['savings_goals'] as List? ?? []).length,
    };
  }

  Future<void> restoreFromJson(String jsonText) async {
    preview(jsonText); // validate first
    final data = jsonDecode(jsonText) as Map<String, dynamic>;
    // Safety backup of the current state before replacing anything.
    await exportToFile();
    List<Map<String, dynamic>> rows(String key) =>
        (data[key] as List).cast<Map<String, dynamic>>();
    List<Map<String, dynamic>> rowsOrEmpty(String key) =>
        ((data[key] as List?) ?? []).cast<Map<String, dynamic>>();
    await db.transaction(() async {
      await db.delete(db.transactions).go();
      await db.delete(db.budgets).go();
      await db.delete(db.savingsGoals).go();
      await db.delete(db.persons).go();
      await db.delete(db.categories).go();
      await db.delete(db.accounts).go();
      for (final r in rows('accounts')) {
        await db.into(db.accounts).insert(AccountsCompanion(
              id: Value(r['id'] as int),
              name: Value(r['name'] as String),
              type: Value(r['type'] as String),
              openingPaisa: Value(r['openingPaisa'] as int),
              sortOrder: Value(r['sortOrder'] as int),
              isArchived: Value(r['isArchived'] as bool),
            ));
      }
      for (final r in rows('categories')) {
        await db.into(db.categories).insert(CategoriesCompanion(
              id: Value(r['id'] as int),
              name: Value(r['name'] as String),
              kind: Value(r['kind'] as String),
              icon: Value(r['icon'] as String),
              isCustom: Value(r['isCustom'] as bool),
              sortOrder: Value(r['sortOrder'] as int),
            ));
      }
      for (final r in rows('persons')) {
        await db.into(db.persons).insert(PersonsCompanion(
              id: Value(r['id'] as int),
              name: Value(r['name'] as String),
              phone: Value(r['phone'] as String),
              note: Value(r['note'] as String),
              createdAt: Value(DateTime.parse(r['createdAt'] as String)),
            ));
      }
      for (final r in rowsOrEmpty('savings_goals')) {
        await db.into(db.savingsGoals).insert(SavingsGoalsCompanion(
              id: Value(r['id'] as int),
              name: Value(r['name'] as String),
              targetPaisa: Value(r['targetPaisa'] as int),
              createdAt: Value(DateTime.parse(r['createdAt'] as String)),
            ));
      }
      for (final r in rows('transactions')) {
        await db.into(db.transactions).insert(TransactionsCompanion(
              id: Value(r['id'] as int),
              type: Value(r['type'] as String),
              amountPaisa: Value(r['amountPaisa'] as int),
              accountId: Value(r['accountId'] as int),
              toAccountId: Value(r['toAccountId'] as int?),
              categoryId: Value(r['categoryId'] as int?),
              personId: Value(r['personId'] as int?),
              note: Value(r['note'] as String),
              occurredAt: Value(DateTime.parse(r['occurredAt'] as String)),
              createdAt: Value(DateTime.parse(r['createdAt'] as String)),
              reversesId: Value(r['reversesId'] as int?),
              isReversed: Value(r['isReversed'] as bool),
              savingsGoalId: Value(r['savingsGoalId'] as int?),
            ));
      }
      for (final r in rows('budgets')) {
        await db.into(db.budgets).insert(BudgetsCompanion(
              id: Value(r['id'] as int),
              categoryId: Value(r['categoryId'] as int?),
              limitPaisa: Value(r['limitPaisa'] as int),
            ));
      }
    });
  }
}
