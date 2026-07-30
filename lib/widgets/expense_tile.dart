import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/expense.dart';
import 'category_icon.dart';
import 'pressable.dart';

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    super.key,
    required this.expense,
    this.onTap,
    this.showDate = true,
  });

  final Expense expense;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    // The title is what was bought; the line under it carries whatever is left
    // over — category, note, and the date when the list is not day-grouped.
    final details = <String>[
      expense.category.label,
      if (expense.item.trim().isNotEmpty && expense.note.trim().isNotEmpty)
        expense.note.trim(),
      if (showDate) Dates.relativeDay(expense.date),
    ];
    final subtitle = details.join(' · ');

    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            CategoryIcon(category: expense.category),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: viz.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: viz.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              Money.format(expense.amount),
              style: context.text.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: viz.inkPrimary,
                letterSpacing: -0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
