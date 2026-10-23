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
  'family': Icons.family_restroom_rounded,
  'other': Icons.more_horiz_rounded,
  // Glyphs for categories learned from notes (catalog noteIconHints).
  'milk': Icons.local_drink_rounded,
  'egg': Icons.egg_rounded,
  'bread': Icons.bakery_dining_rounded,
  'tea': Icons.emoji_food_beverage_rounded,
  'coffee': Icons.coffee_rounded,
  'vegetable': Icons.eco_rounded,
  'fruit': Icons.spa_rounded,
  'meat': Icons.kebab_dining_rounded,
  'juice': Icons.blender_rounded,
  'sweets': Icons.cake_rounded,
  'icecream': Icons.icecream_rounded,
  'bus': Icons.directions_bus_rounded,
  'taxi': Icons.local_taxi_rounded,
  'book': Icons.menu_book_rounded,
  'hospital': Icons.local_hospital_rounded,
  'gift': Icons.card_giftcard_rounded,
  'salon': Icons.content_cut_rounded,
  'laundry': Icons.local_laundry_service_rounded,
  'water': Icons.water_drop_rounded,
  'toys': Icons.toys_rounded,
  'gym': Icons.fitness_center_rounded,
  'label': Icons.label_rounded,
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
