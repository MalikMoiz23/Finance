import 'package:flutter/material.dart';

/// Eight spending classes — the ceiling for colour-carrying categories. Each one
/// owns a fixed slot from the validated categorical palette (slots 2..8, plus
/// muted grey for `other`); slot 1's blue is reserved for magnitude marks.
///
/// The hue follows the *entity*, never its rank, so filtering or re-sorting the
/// breakdown never repaints a category. Colour is only ever used on small icon
/// chips that also carry an icon glyph and a text label, so identity is never
/// colour-alone.
enum ExpenseCategory {
  groceries(
    'Groceries',
    Icons.shopping_basket_rounded,
    Color(0xFF008300), // slot 6 green (mode-invariant)
    Color(0xFF008300),
  ),
  fuel(
    'Fuel & Transport',
    Icons.local_gas_station_rounded,
    Color(0xFFEB6834), // slot 2 orange
    Color(0xFFD95926),
  ),
  dining(
    'Dining Out',
    Icons.restaurant_rounded,
    Color(0xFFE34948), // slot 8 red
    Color(0xFFE66767),
  ),
  bills(
    'Bills & Utilities',
    Icons.receipt_long_rounded,
    Color(0xFFEDA100), // slot 4 yellow
    Color(0xFFC98500),
  ),
  rent(
    'Rent & Home',
    Icons.home_rounded,
    Color(0xFF4A3AA7), // slot 7 violet
    Color(0xFF9085E9),
  ),
  health(
    'Health',
    Icons.favorite_rounded,
    Color(0xFF1BAF7A), // slot 3 aqua
    Color(0xFF199E70),
  ),
  shopping(
    'Shopping',
    Icons.shopping_bag_rounded,
    Color(0xFFE87BA4), // slot 5 magenta
    Color(0xFFD55181),
  ),
  other(
    'Other',
    Icons.more_horiz_rounded,
    Color(0xFF898781), // muted ink — the tail class, not a categorical slot
    Color(0xFF898781),
  );

  const ExpenseCategory(this.label, this.icon, this._light, this._dark);

  final String label;
  final IconData icon;
  final Color _light;
  final Color _dark;

  Color color(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  Color colorOf(BuildContext context) => color(Theme.of(context).brightness);

  static ExpenseCategory fromName(String name) => ExpenseCategory.values
      .firstWhere((c) => c.name == name, orElse: () => ExpenseCategory.other);
}
