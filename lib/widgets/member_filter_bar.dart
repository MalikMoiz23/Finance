import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../state/expense_store.dart';

/// A filter choice in a horizontal row: a person, a category, "All".
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dotColor;

  /// Used by the people row, where there is no category colour to show a dot
  /// for and the pills need something to tell them apart from the categories.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? viz.inkPrimary : viz.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: selected ? viz.inkPrimary : viz.hairline),
        ),
        child: Row(
          children: [
            if (dotColor != null) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ],
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? viz.surface : viz.inkMuted,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: context.text.labelLarge?.copyWith(
                color: selected ? viz.surface : viz.inkSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whose spending the screen shows: everyone, one person, or the expenses with
/// nobody attached.
///
/// The choice lives in the store, not the screen, so picking Abba on the
/// Overview also narrows Insights and Expenses — the same way the period does.
/// Hidden until the household has people in it.
class MemberFilterBar extends StatelessWidget {
  const MemberFilterBar({super.key, this.padding = EdgeInsets.zero});

  /// Horizontal inset for the scrolling row, so it can bleed to the screen
  /// edge on a list whose cards sit inside a gutter.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    if (!store.hasMembers) return const SizedBox.shrink();
    final selected = store.memberFilter;

    void toggle(String id) => store.setMemberFilter(selected == id ? null : id);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          FilterPill(
            label: 'Everyone',
            icon: Icons.groups_rounded,
            selected: selected == null,
            onTap: () => store.setMemberFilter(null),
          ),
          for (final member in store.members) ...[
            const SizedBox(width: 8),
            FilterPill(
              label: member.name,
              icon: Icons.person_rounded,
              selected: selected == member.id,
              onTap: () => toggle(member.id),
            ),
          ],
          if (store.unassignedExpenseCount > 0 ||
              selected == ExpenseStore.unassignedMember) ...[
            const SizedBox(width: 8),
            FilterPill(
              label: 'Not set',
              icon: Icons.help_outline_rounded,
              selected: selected == ExpenseStore.unassignedMember,
              onTap: () => toggle(ExpenseStore.unassignedMember),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown under the filter bar while one person is selected: whose figures
/// these are, and the one thing the filter does not narrow.
class MemberFilterNote extends StatelessWidget {
  const MemberFilterNote({super.key, this.total});

  /// That person's total for the period, when the screen has no hero figure
  /// of its own to show it.
  final double? total;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final name = store.memberFilterLabel;
    if (name == null) return const SizedBox.shrink();
    final viz = context.viz;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: viz.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt_rounded, size: 16, color: viz.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              total == null
                  ? 'Showing $name only · pay and budgets stay household-wide'
                  : '$name · ${Money.format(total!)} · pay and budgets stay '
                        'household-wide',
              style: context.text.labelSmall?.copyWith(
                color: viz.inkSecondary,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: () => store.setMemberFilter(null),
            style: TextButton.styleFrom(
              foregroundColor: viz.series,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: const Text('Show all'),
          ),
        ],
      ),
    );
  }
}
