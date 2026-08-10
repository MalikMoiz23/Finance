import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/income.dart';
import 'delta_badge.dart';
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
///
/// A full card with a real button rather than a chevron row: this is the one
/// thing standing between the user and savings tracking, so it has to read as an
/// action, not as another list item.
class _SetPayPrompt extends StatelessWidget {
  const _SetPayPrompt({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: viz.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: viz.successText.withValues(alpha: 0.45)),
        boxShadow: context.isDarkMode
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0F0B0B0B),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: viz.successText.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.payments_rounded,
                  size: 22,
                  color: viz.successText,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add your income',
                      style: context.text.titleSmall?.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Track savings, not just spending',
                      style: context.text.bodySmall?.copyWith(
                        color: viz.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Enter what you earn each month and this card shows what you have '
            'left after expenses, and whether you saved more than last month.',
            style: context.text.bodySmall?.copyWith(
              color: viz.inkSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Set monthly income'),
              style: FilledButton.styleFrom(
                backgroundColor: viz.successText,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: context.text.titleSmall?.copyWith(
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
