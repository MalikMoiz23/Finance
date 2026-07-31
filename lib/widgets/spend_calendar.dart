import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';

/// A month of spending as a heatmap: one cell per day, darker where more was
/// spent.
///
/// This is **sequential** encoding — magnitude, not identity — so it uses a
/// single hue stepped light to dark from the project's blue ramp, never a set of
/// categorical colours. In dark mode the ramp is anchored the other way round
/// (near-surface for the smallest values), so "more" always means "further from
/// the background". A scale legend sits under the grid, and every cell carries
/// its exact total in its screen-reader label, so colour is never the only way
/// to read a value.
class SpendCalendar extends StatelessWidget {
  const SpendCalendar({
    super.key,
    required this.month,
    required this.dailyTotals,
    required this.selected,
    required this.onSelect,
  });

  /// Any date inside the month to draw.
  final DateTime month;

  final Map<DateTime, double> dailyTotals;
  final DateTime? selected;
  final ValueChanged<DateTime?> onSelect;

  // Blue ramp steps 100 -> 650, then the dark-mode set anchored from 700 up.
  static const _lightRamp = [
    Color(0xFFCDE2FB),
    Color(0xFF9EC5F4),
    Color(0xFF6DA7EC),
    Color(0xFF2A78D6),
    Color(0xFF104281),
  ];
  static const _darkRamp = [
    Color(0xFF0D366B),
    Color(0xFF184F95),
    Color(0xFF256ABF),
    Color(0xFF3987E5),
    Color(0xFF86B6EF),
  ];

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final ramp = context.isDarkMode ? _darkRamp : _lightRamp;

    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Monday-first grid
    final today = dayOnly(DateTime.now());
    final peak = dailyTotals.values.fold<double>(0, (m, v) => v > m ? v : m);

    /// 0 = nothing spent, 1..5 = increasing share of the busiest day.
    int levelFor(double total) {
      if (total <= 0 || peak <= 0) return 0;
      final share = total / peak;
      if (share <= 0.2) return 1;
      if (share <= 0.4) return 2;
      if (share <= 0.6) return 3;
      if (share <= 0.8) return 4;
      return 5;
    }

    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const _Cell.blank(),
      for (var day = 1; day <= daysInMonth; day++)
        () {
          final date = DateTime(month.year, month.month, day);
          final total = dailyTotals[date] ?? 0;
          final level = levelFor(total);
          return _Cell(
            day: day,
            total: total,
            fill: level == 0 ? viz.surfaceAlt : ramp[level - 1],
            // White ink only on the two darkest fills in light mode; in dark
            // mode the top steps are the light ones, so it inverts.
            onFill: level >= 4
                ? (context.isDarkMode ? const Color(0xFF0B0B0B) : Colors.white)
                : viz.inkSecondary,
            isToday: date == today,
            isSelected: selected != null && dayOnly(selected!) == date,
            onTap: () => onSelect(
              selected != null && dayOnly(selected!) == date ? null : date,
            ),
          );
        }(),
    ];

    // Pad to a whole week so the last row keeps the same cell width.
    while (cells.length % 7 != 0) {
      cells.add(const _Cell.blank());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: context.text.labelSmall?.copyWith(
                      color: viz.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < cells.length / 7; row++) ...[
          if (row > 0) const SizedBox(height: 5),
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: cells[row * 7 + col],
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Less',
              style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
            ),
            const SizedBox(width: 6),
            for (final step in [viz.surfaceAlt, ...ramp]) ...[
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: step,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: viz.hairline),
                ),
              ),
              const SizedBox(width: 3),
            ],
            const SizedBox(width: 3),
            // The top of the scale is the busiest day's total, so the ramp is
            // readable as a quantity rather than just "more".
            Flexible(
              child: Text(
                peak > 0 ? Money.compact(peak) : 'More',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.total,
    required this.fill,
    required this.onFill,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  const _Cell.blank()
    : day = null,
      total = 0,
      fill = null,
      onFill = null,
      isToday = false,
      isSelected = false,
      onTap = null;

  final int? day;
  final double total;
  final Color? fill;
  final Color? onFill;
  final bool isToday;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (day == null) return const AspectRatio(aspectRatio: 1);
    final viz = context.viz;

    return Semantics(
      button: true,
      selected: isSelected,
      label: total > 0
          ? 'Day $day, ${Money.format(total)}'
          : 'Day $day, nothing spent',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(9),
              border: isSelected
                  ? Border.all(color: viz.inkPrimary, width: 2)
                  : isToday
                  ? Border.all(color: viz.series, width: 1.6)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: context.text.labelSmall?.copyWith(
                color: onFill,
                fontWeight: isToday || isSelected
                    ? FontWeight.w800
                    : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
