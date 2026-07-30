import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../models/period.dart';
import '../state/expense_store.dart';

/// The one filter row for the whole app: it scopes every chart, stat and list
/// below it, so no card carries its own range control and the numbers always
/// agree.
class PeriodFilterBar extends StatelessWidget {
  const PeriodFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final relative = store.relativeRangeLabel;

    return Column(
      children: [
        _PeriodPills(selected: store.period, onChanged: store.setPeriod),
        const SizedBox(height: 10),
        Row(
          children: [
            _StepButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Previous ${store.period.noun}',
              onTap: () => store.stepPeriod(-1),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: relative == null ? store.jumpToToday : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Text(
                        store.rangeLabel,
                        style: context.text.titleSmall?.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        relative ?? 'Tap to jump back to today',
                        style: context.text.labelSmall?.copyWith(
                          color: relative == null
                              ? context.viz.series
                              : context.viz.inkMuted,
                          fontWeight: relative == null
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _StepButton(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Next ${store.period.noun}',
              onTap: store.canGoForward ? () => store.stepPeriod(1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _PeriodPills extends StatelessWidget {
  const _PeriodPills({required this.selected, required this.onChanged});

  final Period selected;
  final ValueChanged<Period> onChanged;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: viz.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final period in Period.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(period),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: period == selected ? viz.series : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      period.label,
                      style: context.text.labelLarge?.copyWith(
                        color: period == selected
                            ? Colors.white
                            : viz.inkSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: viz.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: viz.hairline),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 22,
              color: enabled
                  ? viz.inkSecondary
                  : viz.inkMuted.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
