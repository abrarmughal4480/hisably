import 'package:flutter/material.dart';

import '../data/category_catalog.dart';

/// Glyphs for the category icon NAMES from the catalog module
/// (data/category_catalog.dart is the single source for which category
/// gets which icon name; this file only maps names to glyphs).
/// Every default category has its own proper icon (v0.6.8 icons pass).
const _glyphs = <String, IconData>{
  'groceries': Icons.shopping_basket_rounded,
  'electricity': Icons.bolt_rounded,
  'gas': Icons.local_fire_department_rounded,
  'rent': Icons.home_rounded,
  'school': Icons.school_rounded,
  'petrol': Icons.local_gas_station_rounded,
  'mobile': Icons.smartphone_rounded,
  'internet': Icons.wifi_rounded,
  'food': Icons.restaurant_rounded,
  'travel': Icons.directions_car_rounded,
  'medicine': Icons.medical_services_rounded,
  'clothes': Icons.checkroom_rounded,
  'charity': Icons.volunteer_activism_rounded,
  'zakat': Icons.mosque_rounded,
  'entertainment': Icons.movie_rounded,
  'other': Icons.more_horiz_rounded,
  'salary': Icons.payments_rounded,
  'business': Icons.storefront_rounded,
  'freelancing': Icons.laptop_rounded,
  'profit': Icons.trending_up_rounded,
  'other_income': Icons.account_balance_wallet_rounded,
};

/// Icon for a stored icon name (categories.icon); generic fallback for
/// custom categories and unknown names.
IconData categoryIcon(String? iconName) =>
    _glyphs[iconName] ?? Icons.category_rounded;

/// Icon for a category row: its stored icon name, else the catalog's
/// icon for built-in category names, else the generic glyph.
IconData categoryIconFor(String? iconName, String categoryName) =>
    categoryIcon(iconName ?? CategoryCatalog.iconForName[categoryName]);
