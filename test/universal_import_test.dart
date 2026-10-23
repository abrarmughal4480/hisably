import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/data/universal_import.dart';

/// The Universal Import engine (build 2020): other apps' files in,
/// normalized entries out. Every shape here mirrors a real export
/// style seen in the wild.
void main() {
  group('delimited parsing', () {
    test('comma CSV with quoted notes', () {
      final t = parseDelimited(
          'Date,Category,Amount,Note\n'
          '2026-10-01,Food,-450.50,"Lunch, with friends"\n'
          '2026-10-02,Salary,85000,October pay\n');
      expect(t.headers, ['Date', 'Category', 'Amount', 'Note']);
      expect(t.rows.length, 2);
      expect(t.rows[0][3], 'Lunch, with friends');
    });

    test('semicolon CSV (European bank style)', () {
      final t = parseDelimited(
          'Date;Description;Debit;Credit\n'
          '02/10/2026;Grocery store;1200;\n'
          '03/10/2026;Salary;;50000\n');
      expect(t.headers.length, 4);
      expect(t.rows.length, 2);
    });
  });

  group('column guessing', () {
    test('Money-Manager-style headers', () {
      final g = guessColumns(
          ['Date', 'Category', 'Amount', 'Note', 'Account']);
      expect(g[ImportField.date], 0);
      expect(g[ImportField.category], 1);
      expect(g[ImportField.amount], 2);
      expect(g[ImportField.note], 3);
      expect(g[ImportField.account], 4);
    });

    test('bank headers with debit/credit pair', () {
      final g = guessColumns(['Date', 'Description', 'Debit', 'Credit']);
      expect(g[ImportField.debit], 2);
      expect(g[ImportField.credit], 3);
      expect(g[ImportField.note], 1);
    });
  });

  group('value parsing', () {
    test('dates in many shapes', () {
      expect(parseFlexibleDate('2026-10-05'), DateTime(2026, 10, 5));
      expect(parseFlexibleDate('05/10/2026'), DateTime(2026, 10, 5));
      expect(parseFlexibleDate('10/25/2026'), DateTime(2026, 10, 25));
      expect(parseFlexibleDate('5 Oct 2026'), DateTime(2026, 10, 5));
      expect(parseFlexibleDate('Oct 5, 2026'), DateTime(2026, 10, 5));
      expect(parseFlexibleDate('1759708800'),
          DateTime.fromMillisecondsSinceEpoch(1759708800000));
      expect(parseFlexibleDate('not a date'), isNull);
    });

    test('amounts in many shapes', () {
      expect(parseAmount('Rs 1,200.50')!.paisa, 120050);
      expect(parseAmount('-250')!.negative, isTrue);
      expect(parseAmount('(500)')!.negative, isTrue);
      expect(parseAmount('PKR 85,000')!.paisa, 8500000);
      expect(parseAmount('abc'), isNull);
    });
  });

  group('entry building', () {
    test('signed single amount column', () {
      final t = parseDelimited(
          'Date,Category,Amount,Note\n'
          '2026-10-01,Food,-450.50,Lunch\n'
          '2026-10-02,Salary,85000,Pay\n'
          'garbage,row,here,x\n');
      final r = buildEntries(
          t,
          guessColumns(t.headers));
      expect(r.entries.length, 2);
      expect(r.skipped, 1);
      expect(r.entries[0].isIncome, isFalse);
      expect(r.entries[0].amountPaisa, 45050);
      expect(r.entries[1].isIncome, isTrue);
      expect(r.totalInPaisa, 8500000);
      expect(r.totalOutPaisa, 45050);
    });

    test('debit/credit pair columns', () {
      final t = parseDelimited(
          'Date;Description;Debit;Credit\n'
          '02/10/2026;Grocery;1200;\n'
          '03/10/2026;Salary;;50000\n');
      final r = buildEntries(t, guessColumns(t.headers));
      expect(r.entries.length, 2);
      expect(r.entries[0].isIncome, isFalse);
      expect(r.entries[0].note, 'Grocery');
      expect(r.entries[1].isIncome, isTrue);
      expect(r.entries[1].amountPaisa, 5000000);
    });

    test('explicit type column overrides sign', () {
      final t = parseDelimited(
          'Date,Type,Amount\n'
          '2026-10-01,Expense,300\n'
          '2026-10-02,Income,900\n');
      final r = buildEntries(t, guessColumns(t.headers));
      expect(r.entries[0].isIncome, isFalse);
      expect(r.entries[1].isIncome, isTrue);
    });

    test('JSON export (array of objects)', () {
      final table = tableFromJson(
          '[{"date":"2026-10-01","category":"Food","amount":-200,"note":"Snacks"},'
          '{"date":"2026-10-03","category":"Fuel","amount":-1500,"note":"Petrol"}]');
      expect(table, isNotNull);
      final r = buildEntries(table!, guessColumns(table.headers));
      expect(r.entries.length, 2);
      expect(r.totalOutPaisa, 170000);
    });
  });
}
