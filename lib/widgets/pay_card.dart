import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/income.dart';
import 'delta_badge.dart';
import 'pressable.dart';
import 'section_card.dart';

/// Pay against spending for the month, what that leaves, and how both compare
/// with last month.
///
/// The meter is share-of-pay-spent — a magnitude, so one hue — and turns to the
/// danger step only when spending passes the pay, where the wording says so too.
class PayCard extends StatelessWidget {
  const PayCard({super.key, required this.comparison, required this.onEdit});

  final MonthComparison comparison;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final now = comparison.current;
    final before = comparison.previous;

    if (!now.hasIncome) {
      return _SetPayPrompt(onEdit: onEdit);
    }

    final pay = now.income!;
    final saved = now.saved!;
    final rate = now.savingsRate;
    final overspent = now.overspent;
    final meterColor = overspent ? viz.critical : viz.series;

    return SectionCard(
      title: 'Pay & savings',
      subtitle: now.carriedForward
          ? '${Dates.monthYear(now.month)} · carried forward'
          : Dates.monthYear(now.month),
      trailing: CardAction(label: 'Edit', onTap: onEdit),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PAY THIS MONTH',
                      style: context.text.labelSmall?.copyWith(
                        color: viz.inkMuted,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      Money.format(pay),
                      style: context.text.titleMedium?.copyWith(
                        fontSize: 22,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ],
                ),
              ),
              if (rate != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: (overspent ? viz.critical : viz.successText)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    overspent
                        ? 'over by ${(-rate * 100).round()}%'
                        : '${(rate * 100).round()}% saved',
                    style: context.text.labelMedium?.copyWith(
                      color: overspent ? viz.critical : viz.successText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 11,
              color: overspent
                  ? viz.critical.withValues(alpha: 0.20)
                  : viz.seriesTrack,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: now.spentFraction),
                duration: const Duration(milliseconds: 680),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: meterColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Spent',
                  value: Money.format(now.spent),
                  delta: comparison.spentDelta,
                  higherIsBetter: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Figure(
                  label: overspent ? 'Overspent by' : 'Saved',
                  value: Money.format(saved.abs()),
                  valueColor: overspent ? viz.critical : viz.successText,
                  delta: comparison.savedDelta,
                  higherIsBetter: true,
                ),
              ),
            ],
          ),
          if (before.hasIncome) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: viz.hairline),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.history_rounded, size: 15, color: viz.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${Dates.monthShort(before.month)}: '
                    '${before.overspent ? 'overspent' : 'saved'} '
                    '${Money.format((before.saved ?? 0).abs())} of '
                    '${Money.format(before.income!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: viz.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.delta,
    required this.higherIsBetter,
    this.valueColor,
  });

  final String label;
  final String value;
  final double? delta;
  final bool higherIsBetter;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.labelSmall?.copyWith(
            color: viz.inkMuted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: context.text.titleSmall?.copyWith(
              fontSize: 17,
              color: valueColor ?? viz.inkPrimary,
            ),
          ),
        ),
        const SizedBox(height: 7),
        DeltaBadge(
          percent: delta,
          comparedTo: 'last month',
          dense: true,
          higherIsBetter: higherIsBetter,
        ),
      ],
    );
  }
}

/// Shown until a pay figure exists — savings cannot be computed without one.
class _SetPayPrompt extends StatelessWidget {
  const _SetPayPrompt({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Pressable(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: viz.surface,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          border: Border.all(color: viz.hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: viz.successText.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.payments_rounded,
                size: 19,
                color: viz.successText,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add your monthly pay',
                    style: context.text.titleSmall?.copyWith(fontSize: 14.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'See what you keep each month, not just what you spend',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: viz.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: viz.inkMuted),
          ],
        ),
      ),
    );
  }
}
