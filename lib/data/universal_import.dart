import 'dart:convert';

/// Universal Import engine (user feature, build 2020).
///
/// Purpose (user, 23 Oct 2026): someone switching to Hisably from
/// another app should be able to bring their data with them. Other
/// apps and banks export CSV (or flat JSON) with wildly different
/// column names and date/amount styles — this engine parses the
/// file, guesses which column is which, and normalizes every row
/// into a [ParsedEntry]. The guess is always shown to the user for
/// confirmation before anything is saved; money values are never
/// silently invented — unparseable rows are skipped and counted.
enum ImportField { date, amount, debit, credit, type, category, note, account }

class ImportTable {
  ImportTable(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;

  String cell(List<String> row, int? col) =>
      (col == null || col < 0 || col >= row.length) ? '' : row[col].trim();
}

/// One normalized transaction ready to be written to the ledger.
class ParsedEntry {
  ParsedEntry({
    required this.date,
    required this.amountPaisa,
    required this.isIncome,
    required this.category,
    required this.note,
    required this.accountName,
  });
  final DateTime date;

  /// Always positive; direction lives in [isIncome].
  final int amountPaisa;
  final bool isIncome;
  final String category; // '' = uncategorized
  final String note;
  final String accountName; // '' = importer's chosen account
}

class ImportParseResult {
  ImportParseResult(this.entries, this.skipped, this.warnings);
  final List<ParsedEntry> entries;
  final int skipped;
  final List<String> warnings;

  int get totalInPaisa =>
      entries.where((e) => e.isIncome).fold(0, (s, e) => s + e.amountPaisa);
  int get totalOutPaisa =>
      entries.where((e) => !e.isIncome).fold(0, (s, e) => s + e.amountPaisa);
}

// ── File parsing ────────────────────────────────────────────────

/// Parses CSV/TSV text. The delimiter is auto-detected from the
/// header line (comma, semicolon, or tab — whichever appears most
/// outside quotes). Quoted fields with embedded delimiters and
/// newlines are handled.
ImportTable parseDelimited(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final firstLine = normalized.split('\n').first;
  final delimiter = _detectDelimiter(firstLine);
  final records = _splitRecords(normalized, delimiter);
  if (records.isEmpty) return ImportTable(const [], const []);
  return ImportTable(records.first, records.skip(1).where((r) => r.any((c) => c.trim().isNotEmpty)).toList());
}

String _detectDelimiter(String headerLine) {
  var best = ',';
  var bestCount = -1;
  for (final d in [',', ';', '\t']) {
    var inQuotes = false;
    var count = 0;
    for (var i = 0; i < headerLine.length; i++) {
      final ch = headerLine[i];
      if (ch == '"') inQuotes = !inQuotes;
      if (ch == d && !inQuotes) count++;
    }
    if (count > bestCount) {
      bestCount = count;
      best = d;
    }
  }
  return best;
}

List<List<String>> _splitRecords(String text, String delimiter) {
  final records = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field = StringBuffer();
  }

  void endRow() {
    endField();
    records.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(ch);
      i++;
      continue;
    }
    if (ch == '"') {
      inQuotes = true;
    } else if (ch == delimiter) {
      endField();
    } else if (ch == '\n') {
      endRow();
    } else {
      field.write(ch);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return records;
}

/// Flat JSON: an array of objects (most app exports), or an object
/// holding such an array under any key. Headers are the union of
/// object keys in first-seen order.
ImportTable? tableFromJson(String text) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    return null;
  }
  List<dynamic>? list;
  if (decoded is List) {
    list = decoded;
  } else if (decoded is Map) {
    for (final v in decoded.values) {
      if (v is List) {
        list = v;
        break;
      }
    }
  }
  if (list == null || list.isEmpty) return null;
  final headers = <String>[];
  for (final item in list) {
    if (item is Map) {
      for (final k in item.keys) {
        final key = k.toString();
        if (!headers.contains(key)) headers.add(key);
      }
    }
  }
  if (headers.isEmpty) return null;
  final rows = <List<String>>[];
  for (final item in list) {
    if (item is! Map) continue;
    rows.add([for (final h in headers) item[h]?.toString() ?? '']);
  }
  return ImportTable(headers, rows);
}

// ── Column guessing ─────────────────────────────────────────────

const _keywords = <ImportField, List<String>>{
  ImportField.date: [
    'date', 'day', 'tareekh', 'tarikh', 'datetime', 'time', 'posted',
    'transaction date', 'value date',
  ],
  ImportField.amount: [
    'amount', 'value', 'sum', 'rakam', 'total', 'rs', 'pkr', 'money',
    'price', 'cost',
  ],
  ImportField.debit: [
    'debit', 'withdrawal', 'withdraw', 'out', 'expense', 'paid', 'spent',
    'dr',
  ],
  ImportField.credit: [
    'credit', 'deposit', 'in', 'income', 'received', 'cr',
  ],
  ImportField.type: [
    'type', 'kind', 'direction', 'flow', 'category type', 'in/out',
  ],
  ImportField.category: [
    'category', 'head', 'mad', 'group', 'tag', 'class', 'expense head',
  ],
  ImportField.note: [
    'note', 'description', 'desc', 'details', 'detail', 'narration',
    'memo', 'title', 'name', 'particulars', 'remarks', 'comment',
  ],
  ImportField.account: [
    'account', 'wallet', 'source', 'bank', 'from account', 'mode',
  ],
};

/// Guesses a column index per field from header names. Exact
/// (normalized) matches beat substring matches; a column is used
/// for at most one field, in priority order: date, debit/credit,
/// amount, type, category, account, note.
Map<ImportField, int?> guessColumns(List<String> headers) {
  final norm = [
    for (final h in headers) h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim()
  ];
  final used = <int>{};
  final result = <ImportField, int?>{};

  int? find(ImportField field) {
    final words = _keywords[field]!;
    // Exact match first.
    for (var i = 0; i < norm.length; i++) {
      if (used.contains(i)) continue;
      if (words.contains(norm[i])) return i;
    }
    // Then "header contains keyword" / "keyword contains header".
    for (var i = 0; i < norm.length; i++) {
      if (used.contains(i) || norm[i].isEmpty) continue;
      for (final w in words) {
        if (norm[i].contains(w) || w.contains(norm[i])) return i;
      }
    }
    return null;
  }

  for (final field in [
    ImportField.date,
    ImportField.debit,
    ImportField.credit,
    ImportField.amount,
    // Category before Type: a "Category" header must never be
    // claimed by the Type matcher (its keywords include phrases
    // like "category type").
    ImportField.category,
    ImportField.type,
    ImportField.account,
    ImportField.note,
  ]) {
    final idx = find(field);
    result[field] = idx;
    if (idx != null) used.add(idx);
  }
  return result;
}

// ── Value parsing ───────────────────────────────────────────────

/// Parses dates in the shapes real exports use: ISO, dd/MM/yyyy,
/// dd-MM-yyyy, MM/dd/yyyy (disambiguated when possible, dd/MM
/// preferred — the PK/IN convention), 'dd MMM yyyy', 'MMM dd yyyy',
/// and epoch seconds/milliseconds.
DateTime? parseFlexibleDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  // Epoch FIRST: DateTime.tryParse happily misreads a bare epoch
  // string as a compact ISO date with an absurd year.
  if (RegExp(r'^\d{10}(\.\d+)?$').hasMatch(s)) {
    return DateTime.fromMillisecondsSinceEpoch(
        (double.parse(s) * 1000).round());
  }
  if (RegExp(r'^\d{13}$').hasMatch(s)) {
    return DateTime.fromMillisecondsSinceEpoch(int.parse(s));
  }
  final iso = DateTime.tryParse(s);
  if (iso != null && iso.year >= 1990 && iso.year <= 2100) return iso;
  final m = RegExp(r'^(\d{1,2})[/\-. ](\d{1,2})[/\-. ](\d{2,4})$').firstMatch(s);
  if (m != null) {
    var a = int.parse(m.group(1)!);
    var b = int.parse(m.group(2)!);
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    int day, month;
    if (a > 12 && b <= 12) {
      day = a;
      month = b;
    } else if (b > 12 && a <= 12) {
      month = a;
      day = b;
    } else {
      day = a; // dd/MM preferred
      month = b;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(y, month, day);
  }
  final named = RegExp(
          r'^(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{4})$|^([A-Za-z]{3,9})\s+(\d{1,2}),?\s+(\d{4})$')
      .firstMatch(s);
  if (named != null) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final g = named.groups([1, 2, 3, 4, 5, 6]);
    final day = int.tryParse(g[0] ?? g[4] ?? '');
    final monName = (g[1] ?? g[3] ?? '').toLowerCase();
    final year = int.tryParse(g[2] ?? g[5] ?? '');
    final month = months[monName.substring(0, 3)];
    if (day != null && month != null && year != null) {
      return DateTime(year, month, day);
    }
  }
  return null;
}

/// Parses an amount into paisa (positive value + sign returned
/// separately via [signed]). Strips currency symbols/text and
/// thousands separators; parentheses mean negative; a trailing or
/// leading minus means negative. Exports are in rupees — the value
/// is multiplied by 100.
({int paisa, bool negative})? parseAmount(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  var negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  }
  s = s
      .replaceAll(RegExp(r'pkr|rs\.?|inr|usd', caseSensitive: false), '')
      .replaceAll(RegExp(r'[₹$€£,\s]'), '');
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  } else if (s.endsWith('-')) {
    negative = true;
    s = s.substring(0, s.length - 1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  final value = double.tryParse(s);
  if (value == null) return null;
  return (paisa: (value * 100).round(), negative: negative);
}

bool? _typeFromText(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  const income = {
    'income', 'in', 'credit', 'cr', 'deposit', 'received', 'receive',
    'earning', 'salary', 'refund', '+',
  };
  const expense = {
    'expense', 'out', 'debit', 'dr', 'withdrawal', 'withdraw', 'paid',
    'spent', 'payment', 'purchase', '-',
  };
  if (income.contains(s)) return true;
  if (expense.contains(s)) return false;
  if (s.contains('income') || s.contains('credit')) return true;
  if (s.contains('expense') || s.contains('debit')) return false;
  return null;
}

// ── Row normalization ───────────────────────────────────────────

/// Builds entries from [table] using [mapping] (field → column
/// index, null = unused). Rows that lack a usable date or amount
/// are skipped and counted — never guessed.
ImportParseResult buildEntries(
    ImportTable table, Map<ImportField, int?> mapping) {
  final entries = <ParsedEntry>[];
  final warnings = <String>[];
  var skipped = 0;

  final dateCol = mapping[ImportField.date];
  final amountCol = mapping[ImportField.amount];
  final debitCol = mapping[ImportField.debit];
  final creditCol = mapping[ImportField.credit];
  final typeCol = mapping[ImportField.type];
  final categoryCol = mapping[ImportField.category];
  final noteCol = mapping[ImportField.note];
  final accountCol = mapping[ImportField.account];

  for (final row in table.rows) {
    final dateText = table.cell(row, dateCol);
    final date = dateCol == null ? null : parseFlexibleDate(dateText);

    int? paisa;
    bool? isIncome;
    final typeText = table.cell(row, typeCol);
    final fromType = _typeFromText(typeText);

    if (debitCol != null || creditCol != null) {
      final d = parseAmount(table.cell(row, debitCol));
      final c = parseAmount(table.cell(row, creditCol));
      if (c != null && c.paisa > 0) {
        paisa = c.paisa;
        isIncome = true;
      } else if (d != null && d.paisa > 0) {
        paisa = d.paisa;
        isIncome = false;
      }
    }
    if (paisa == null && amountCol != null) {
      final a = parseAmount(table.cell(row, amountCol));
      if (a != null && a.paisa > 0) {
        paisa = a.paisa;
        // An explicit type column wins; otherwise the sign speaks:
        // negative = expense, positive = income (the common
        // single-column convention).
        isIncome = fromType ?? !a.negative;
      }
    }

    if (date == null || paisa == null || paisa <= 0 || isIncome == null) {
      skipped++;
      continue;
    }
    entries.add(ParsedEntry(
      date: date,
      amountPaisa: paisa,
      isIncome: isIncome,
      category: table.cell(row, categoryCol),
      note: table.cell(row, noteCol),
      accountName: table.cell(row, accountCol),
    ));
  }
  if (skipped > 0) {
    warnings.add('$skipped row(s) skipped — missing or unreadable date/amount');
  }
  entries.sort((a, b) => a.date.compareTo(b.date));
  return ImportParseResult(entries, skipped, warnings);
}
