import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import 'khata_person_screen.dart';

class KhataScreen extends ConsumerWidget {
  const KhataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final persons = ref.watch(personsProvider);
    final txs = ref.watch(transactionsProvider).value ?? [];
    final index = ref.watch(ledgerIndexProvider);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(s.t('khata'),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                FilledButton.icon(
                  onPressed: () => _addPerson(context, ref),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(s.t('addPerson')),
                  style: FilledButton.styleFrom(
                      backgroundColor: HisablyColors.primary),
                ),
              ],
            ),
          ),
          Expanded(
            child: persons.when(
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Text(s.t('noPersons'),
                        textAlign: TextAlign.center),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final person = list[i];
                    final net = index?.outstandingOf(person.id) ??
                        outstandingOf(person.id, txs);
                    return Card(
                      child: ListTile(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    KhataPersonScreen(person: person))),
                        leading: CircleAvatar(
                          backgroundColor: HisablyColors.primaryTint,
                          child: Text(
                            person.name.characters.take(2).toUpperCase().toString(),
                            style: const TextStyle(
                                color: HisablyColors.primaryDeep,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Text(person.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(net == 0
                            ? s.t('settled')
                            : net > 0
                                ? s.t('theyOweYou')
                                : s.t('youOweThem')),
                        trailing: Text(
                          formatPaisa(net.abs()),
                          style: TextStyle(
                            color: net == 0
                                ? HisablyColors.textSecondary
                                : net > 0
                                    ? HisablyColors.income
                                    : HisablyColors.expense,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addPerson(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('newPerson')),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(labelText: s.t('name')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
              child: Text(s.t('add'))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final db = ref.read(databaseProvider);
    await db.into(db.persons).insert(PersonsCompanion.insert(
          name: name,
          createdAt: DateTime.now(),
        ));
  }
}
