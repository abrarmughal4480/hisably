import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/data/backup_service.dart';
import 'package:hisably/data/database.dart';
import 'package:hisably/data/repository.dart';

class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = FakePathProvider();

  test('backup export and restore round-trips all data', () async {
    final db1 = HisablyDatabase.forTesting(NativeDatabase.memory());
    final repo = LedgerRepository(db1);
    await repo.seedCategoriesIfEmpty();
    final cashId = await repo.addAccount('Cash');
    final accounts = await db1.select(db1.accounts).get();
    final personId = await db1.into(db1.persons).insert(
        PersonsCompanion.insert(name: 'Ahmed', createdAt: DateTime(2026, 10, 1)));
    await repo.addTransaction(TransactionsCompanion.insert(
      type: 'lend',
      amountPaisa: 1500000,
      accountId: cashId,
      personId: Value(personId),
      occurredAt: DateTime(2026, 10, 2),
      createdAt: DateTime(2026, 10, 2),
    ));
    final service = BackupService(db1);
    final json = await service.exportToJson();
    expect(service.preview(json)['transactions'], 1);
    await db1.close();

    final db2 = HisablyDatabase.forTesting(NativeDatabase.memory());
    final service2 = BackupService(db2);
    await service2.restoreFromJson(json);
    final repo2 = LedgerRepository(db2);
    expect(await repo2.totalLenayPaisa(), 1500000);
    final restoredAccounts = await db2.select(db2.accounts).get();
    expect(restoredAccounts.length, accounts.length);
    await db2.close();
  });

  test('preview rejects foreign files', () async {
    final db = HisablyDatabase.forTesting(NativeDatabase.memory());
    final service = BackupService(db);
    expect(() => service.preview('{"app":"Other","backupVersion":1}'),
        throwsFormatException);
    await db.close();
  });
}
