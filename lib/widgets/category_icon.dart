import 'package:flutter/material.dart';

import '../models/expense_category.dart';

/// A category's colour only ever appears here — a small tinted chip that always
/// sits beside the category's icon and its text label, so identity never rests
/// on hue alone.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon({
    super.key,
    required this.category,
    this.size = 42,
    this.iconSize = 21,
    this.selected = false,
  });

  final ExpenseCategory category;
  final double size;
  final double iconSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = category.color(Theme.of(context).brightness);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: selected ? (dark ? 0.32 : 0.20) : (dark ? 0.22 : 0.13),
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        // A ring in the category's own hue marks selection; a solid fill with a
        // white glyph would drop the lighter slots below text contrast.
        border: selected ? Border.all(color: color, width: 2) : null,
      ),
      child: Icon(category.icon, size: iconSize, color: color),
    );
  }
}
