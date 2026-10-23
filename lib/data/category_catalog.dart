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
    'Clothes', 'Charity', 'Zakat', 'Entertainment', 'Other',
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
}
