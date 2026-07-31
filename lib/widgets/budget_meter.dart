import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/budget.dart';
import 'category_icon.dart';
import 'pressable.dart';

/// Colour for a budget band. This is a **meter**, so the fill carries severity
/// (accent → warning → danger) and the track is a faint step of the same hue.
/// The band is always spelled out in words beside an icon, so the state never
/// rests on colour.
({Color fill, Color track, IconData icon}) bandStyle(
  BuildContext context,
  BudgetBand band,
) {
  final viz = context.viz;
  return switch (band) {
    BudgetBand.onTrack => (
      fill: viz.series,
      track: viz.seriesTrack,
      icon: Icons.check_circle_rounded,
    ),
    BudgetBand.closeToLimit => (
      fill: viz.warning,
      track: viz.warning.withValues(alpha: 0.22),
      icon: Icons.warning_amber_rounded,
    ),
    BudgetBand.overBudget => (
      fill: viz.critical,
      track: viz.critical.withValues(alpha: 0.20),
      icon: Icons.error_rounded,
    ),
  };
}

/// One category's monthly limit: spend against limit, an animated meter, and
/// what is left (or what it went over by).
class BudgetRow extends StatelessWidget {
  const BudgetRow({
    super.key,
    required this.status,
    this.onTap,
    this.dense = false,
  });

  final BudgetStatus status;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final style = bandStyle(context, status.band);
    final over = status.band == BudgetBand.overBudget;

    return Pressable(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryIcon(
                category: status.category,
                size: dense ? 36 : 40,
                iconSize: dense ? 18 : 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            status.category.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: viz.inkPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text.rich(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: Money.format(status.spent),
                                  style: context.text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: viz.inkPrimary,
                                  ),
                                ),
                                TextSpan(
                                  text: ' / ${Money.compact(status.limit)}',
                                  style: context.text.bodySmall?.copyWith(
                                    color: viz.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _Meter(
                            fraction: status.meterFraction,
                            fill: style.fill,
                            track: style.track,
                          ),
                        ),
                        // Safe daily spend sits beside the meter, where there is
                        // room, instead of crowding the status line.
                        if (!over && status.daysLeft > 0) ...[
                          const SizedBox(width: 10),
                          Text(
                            '${Money.compact(status.dailyAllowance)}/day',
                            style: context.text.labelSmall?.copyWith(
                              color: viz.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: dense ? 48 : 52),
            child: Row(
              children: [
                Icon(style.icon, size: 14, color: style.fill),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    over
                        ? '${status.band.label} by ${Money.format(-status.remaining)}'
                        : '${status.band.label} · ${Money.format(status.remaining)} left',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      // Warning amber is below text contrast on the light
                      // surface, so wording stays in ink and the icon carries
                      // the colour.
                      color: over ? viz.critical : viz.inkSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.fraction,
    required this.fill,
    required this.track,
  });

  final double fraction;
  final Color fill;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 9,
        color: track,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: fraction),
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact ring used in the dashboard summary: overall spend against the total
/// of every limit set.
class BudgetRing extends StatelessWidget {
  const BudgetRing({
    super.key,
    required this.fraction,
    required this.band,
    this.size = 58,
  });

  final double fraction;
  final BudgetBand band;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = bandStyle(context, band);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: fraction.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 720),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                backgroundColor: style.track,
                valueColor: AlwaysStoppedAnimation(style.fill),
              ),
            ),
            Text(
              '${(fraction * 100).round()}%',
              style: context.text.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.viz.inkPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
