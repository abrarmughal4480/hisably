/// Category catalog — the single source of truth for the built-in
/// categories: their English names, seed order, icon names and the
/// one-time Roman-Urdu → English renames. Pure data, no database and
/// no UI imports, so the repository, the icon widgets and the tests
/// all read from the same module.
class CategoryCatalog {
  const CategoryCatalog._();

  /// Default expense categories, in seed order (pure English only —
  /// user rule, 22 Oct 2026).
  static const expenseNames = <String>[
    'Groceries', 'Electricity', 'Gas', 'Rent', 'School Fees', 'Petrol',
    'Mobile Recharge', 'Internet', 'Food & Drink', 'Travel', 'Medicine',
    'Clothes', 'Charity', 'Zakat', 'Entertainment', 'Family', 'Other',
  ];

  /// Default income categories, in seed order.
  static const incomeNames = <String>[
    'Salary', 'Business', 'Freelancing', 'Profit', 'Other Income',
  ];

  /// Icon NAME stored in categories.icon for each built-in category.
  /// The glyph for a name lives in widgets/category_icons.dart.
  static const iconForName = <String, String>{
    'Groceries': 'groceries',
    'Electricity': 'electricity',
    'Gas': 'gas',
    'Rent': 'rent',
    'School Fees': 'school',
    'Petrol': 'petrol',
    'Mobile Recharge': 'mobile',
    'Internet': 'internet',
    'Food & Drink': 'food',
    'Travel': 'travel',
    'Medicine': 'medicine',
    'Clothes': 'clothes',
    'Charity': 'charity',
    'Zakat': 'zakat',
    'Entertainment': 'entertainment',
    'Family': 'family',
    'Other': 'other',
    'Salary': 'salary',
    'Business': 'business',
    'Freelancing': 'freelancing',
    'Profit': 'profit',
    'Other Income': 'other_income',
  };

  /// One-time renames for existing installs: old Roman-Urdu seed names
  /// → their English replacements.
  static const renames = <String, String>{
    'Rashan': 'Groceries',
    'Bijli': 'Electricity',
    'Kiraya': 'Rent',
    'Mobile Load': 'Mobile Recharge',
    'Khana Peena': 'Food & Drink',
    'Safar': 'Travel',
    'Dawai': 'Medicine',
    'Kapray': 'Clothes',
    'Sadqa': 'Charity',
    'Tafreeh': 'Entertainment',
    'Deegar': 'Other',
    'Tankhwah': 'Salary',
    'Karobar': 'Business',
    'Munafa': 'Profit',
    'Deegar Aamdani': 'Other Income',
  };

  /// Keyword → icon-name hints for categories LEARNED from entry
  /// notes: when a user writes a short note under Other (e.g.
  /// "Milk"), that note becomes a category for next time, and this
  /// map gives it a fitting icon automatically. English + Roman
  /// Urdu spellings. Matching is by whole word (or whole phrase
  /// for keys containing a space), so "nan" never fires inside
  /// "banana". First match wins — put specific keys first.
  static const noteIconHints = <String, String>{
    'cold drink': 'juice',
    'ice cream': 'icecream',
    'double roti': 'bread',
    'milk': 'milk',
    'doodh': 'milk',
    'dahi': 'milk',
    'yogurt': 'milk',
    'egg': 'egg',
    'anda': 'egg',
    'anday': 'egg',
    'bread': 'bread',
    'roti': 'bread',
    'naan': 'bread',
    'nan': 'bread',
    'chai': 'tea',
    'tea': 'tea',
    'coffee': 'coffee',
    'sabzi': 'vegetable',
    'vegetable': 'vegetable',
    'banana': 'fruit',
    'apple': 'fruit',
    'mango': 'fruit',
    'kela': 'fruit',
    'fruit': 'fruit',
    'chicken': 'meat',
    'gosht': 'meat',
    'meat': 'meat',
    'beef': 'meat',
    'mutton': 'meat',
    'rice': 'food',
    'chawal': 'food',
    'biryani': 'food',
    'juice': 'juice',
    'drink': 'juice',
    'mithai': 'sweets',
    'sweet': 'sweets',
    'sweets': 'sweets',
    'cake': 'sweets',
    'biscuit': 'sweets',
    'icecream': 'icecream',
    'bus': 'bus',
    'rickshaw': 'bus',
    'riksha': 'bus',
    'van': 'bus',
    'taxi': 'taxi',
    'uber': 'taxi',
    'careem': 'taxi',
    'book': 'book',
    'books': 'book',
    'kitab': 'book',
    'copy': 'book',
    'stationery': 'book',
    'doctor': 'hospital',
    'hospital': 'hospital',
    'clinic': 'hospital',
    'gift': 'gift',
    'tohfa': 'gift',
    'gifts': 'gift',
    'hair': 'salon',
    'barber': 'salon',
    'salon': 'salon',
    'laundry': 'laundry',
    'dhobi': 'laundry',
    'water': 'water',
    'pani': 'water',
    'toy': 'toys',
    'toys': 'toys',
    'khilona': 'toys',
    'gym': 'gym',
    'shoes': 'clothes',
    'joota': 'clothes',
    'jootay': 'clothes',
    'sandal': 'clothes',
  };

  /// Icon name for a category learned from a note; generic 'label'
  /// when no hint matches.
  static String iconForNote(String note) {
    final lower = note.toLowerCase().trim();
    final words = lower.split(RegExp(r'\s+')).toSet();
    for (final e in noteIconHints.entries) {
      if (e.key.contains(' ')) {
        if (lower.contains(e.key)) return e.value;
      } else if (words.contains(e.key)) {
        return e.value;
      }
    }
    return 'label';
  }
}
