import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/analytics.dart';
import 'delta_badge.dart';
import 'entrance.dart';

/// The one hero figure of the app: what this period cost. Same system sans as
/// everything else, proportional figures, and it scales down rather than
/// overflowing on a long total.
class HeroTotalCard extends StatelessWidget {
  const HeroTotalCard({super.key, required this.summary, required this.label});

  final PeriodSummary summary;

  /// "Spent this month", "Spent in 2026" — names the slice being totalled.
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    // Chrome, not a data mark: deep steps of the series ramp so white ink clears
    // 7:1 on the card.
    final gradient = dark
        ? const [Color(0xFF184F95), Color(0xFF0D366B)]
        : const [Color(0xFF1C5CAB), Color(0xFF104281)];

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF104281).withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Icon(
                Icons.trending_up_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedAmount(
              value: summary.total,
              formatter: Money.format,
              style: context.text.displaySmall?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          DeltaBadge(
            percent: summary.deltaPercent,
            comparedTo: 'last ${summary.period.noun}',
            onSurfaceColor: Colors.white,
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.16)),
          const SizedBox(height: 14),
          Row(
            children: [
              _MiniStat(
                label: 'Per day',
                value: Money.compact(summary.dailyAverage),
              ),
              _MiniStat(label: 'Entries', value: '${summary.count}'),
              _MiniStat(
                label: 'Biggest slice',
                value: summary.topSlice?.category.label ?? '—',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.68),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
