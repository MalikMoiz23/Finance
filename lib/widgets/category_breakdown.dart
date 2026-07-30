import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/analytics.dart';
import 'category_icon.dart';
import 'delta_badge.dart';

/// "Where the money went" — a ranked list, not a pie.
///
/// Form: comparing magnitudes across many classes, so bars in a single hue with
/// the amount and the share directly labelled on every row. A donut would need a
/// colour per slice, and past three simultaneous slices no colour ordering can
/// stay separable under colour-vision deficiency — the ranking keeps identity in
/// the icon + name and spends no colour on it.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({
    super.key,
    required this.slices,
    this.showDelta = false,
    this.comparedTo = 'last period',
    this.maxRows,
  });

  final List<CategorySlice> slices;
  final bool showDelta;
  final String comparedTo;

  /// Rows to render; the rest stay in the full list on the Expenses tab.
  final int? maxRows;

  @override
  Widget build(BuildContext context) {
    final rows = maxRows == null || maxRows! >= slices.length
        ? slices
        : slices.take(maxRows!).toList();

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _SliceRow(
            slice: rows[i],
            showDelta: showDelta,
            comparedTo: comparedTo,
          ),
        ],
      ],
    );
  }
}

class _SliceRow extends StatelessWidget {
  const _SliceRow({
    required this.slice,
    required this.showDelta,
    required this.comparedTo,
  });

  final CategorySlice slice;
  final bool showDelta;
  final String comparedTo;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final percent = slice.share * 100;
    final percentLabel = percent > 0 && percent < 1
        ? '<1%'
        : '${percent.round()}%';

    return Row(
      children: [
        CategoryIcon(category: slice.category, size: 40, iconSize: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      slice.category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: viz.inkPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Money.format(slice.total),
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: viz.inkPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(child: _ShareMeter(share: slice.share)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 34,
                    child: Text(
                      percentLabel,
                      textAlign: TextAlign.right,
                      style: context.text.labelSmall?.copyWith(
                        color: viz.inkSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              if (showDelta) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    DeltaBadge(
                      percent: slice.deltaPercent,
                      comparedTo: comparedTo,
                      dense: true,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${slice.count} ${slice.count == 1 ? 'entry' : 'entries'}',
                      style: context.text.labelSmall?.copyWith(
                        color: viz.inkMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Share of the period total. The track is a lighter step of the fill's own
/// ramp, so the meter reads across its whole length.
class _ShareMeter extends StatelessWidget {
  const _ShareMeter({required this.share});

  final double share;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 7,
        color: viz.seriesTrack,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: share.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 560),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: viz.series,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
