import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Stat tile contract: label · value · optional caption · optional sparkline.
/// The value uses the font's proportional figures (tabular digits make a large
/// standalone number look loose).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.sparkline,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  /// Series for the mini trend; the last point is the current bucket.
  final List<double>? sparkline;

  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final points = sparkline;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: viz.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: emphasis ? viz.series.withValues(alpha: 0.45) : viz.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: viz.inkMuted),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: viz.inkMuted,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: context.text.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6,
                color: viz.inkPrimary,
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 3),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: viz.inkSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (points != null && points.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(height: 24, child: Sparkline(values: points)),
          ],
        ],
      ),
    );
  }
}

/// 2px line in the de-emphasis step, current point in the accent with a 2px
/// surface ring so it stays legible where it crosses the line.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return CustomPaint(
      painter: _SparklinePainter(
        values: values,
        line: viz.seriesDeEmphasis,
        accent: viz.series,
        surface: viz.surface,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.line,
    required this.accent,
    required this.surface,
  });

  final List<double> values;
  final Color line;
  final Color accent;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxValue = values.reduce(math.max);
    final span = maxValue <= 0 ? 1.0 : maxValue;
    const inset = 5.0; // room for the end marker + its ring
    final usableWidth = size.width - inset;
    final usableHeight = size.height - inset * 2;

    Offset pointAt(int i) => Offset(
      usableWidth * i / (values.length - 1),
      inset + usableHeight * (1 - values[i] / span),
    );

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final last = pointAt(values.length - 1);
    canvas.drawCircle(last, 5.5, Paint()..color = surface);
    canvas.drawCircle(last, 4, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      !listEquals(old.values, values) ||
      old.line != line ||
      old.accent != accent ||
      old.surface != surface;
}
