import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Change against the previous period. For spending, **up is bad**, so the
/// status colours are inverted relative to a revenue chart. Always an arrow icon
/// plus a worded label — a status colour never carries the meaning alone.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge({
    super.key,
    required this.percent,
    required this.comparedTo,
    this.onSurfaceColor,
    this.dense = false,
  });

  /// Signed percentage change, or null when there is no baseline.
  final double? percent;

  /// "last month", "last week" — named so the reader knows the baseline.
  final String comparedTo;

  /// Set when the badge sits on a coloured card instead of the chart surface.
  final Color? onSurfaceColor;

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final onCard = onSurfaceColor != null;
    final value = percent;

    if (value == null) {
      return _Shell(
        dense: dense,
        background: onCard
            ? Colors.white.withValues(alpha: 0.16)
            : viz.surfaceAlt,
        child: Text(
          dense ? 'new' : 'No $comparedTo to compare',
          style: _labelStyle(context, onSurfaceColor ?? viz.inkSecondary),
        ),
      );
    }

    final rounded = value.abs() < 0.5 ? 0 : value.round();
    final increased = rounded > 0;
    final flat = rounded == 0;

    final tone = onCard
        ? Colors.white
        : flat
        ? viz.inkSecondary
        : increased
        ? viz.critical
        : viz.successText;

    final icon = flat
        ? Icons.remove_rounded
        : increased
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    // Dense rows name the baseline once in the section subtitle, so the badge
    // only carries the arrow + number. The arrow states the direction; the
    // wording is spelled out for screen readers below.
    final text = dense
        ? (flat ? 'flat' : '${rounded.abs()}%')
        : flat
        ? 'No change vs $comparedTo'
        : '${rounded.abs()}% vs $comparedTo';

    return Semantics(
      label: flat
          ? 'No change compared with $comparedTo'
          : '${rounded.abs()} percent ${increased ? 'more' : 'less'} than $comparedTo',
      excludeSemantics: true,
      child: _Shell(
        dense: dense,
        background: onCard
            ? Colors.white.withValues(alpha: 0.16)
            : tone.withValues(alpha: 0.12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: dense ? 13 : 15, color: tone),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _labelStyle(context, tone),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _labelStyle(BuildContext context, Color color) =>
      (dense ? context.text.labelSmall : context.text.labelMedium)?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      );
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.child,
    required this.background,
    required this.dense,
  });

  final Widget child;
  final Color background;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
    );
  }
}
