import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/analytics.dart';

/// Spend over time, one column per bucket.
///
/// Form: a single series of magnitudes, so one hue (the reserved series blue)
/// with **emphasis** rather than eight categorical colours. The focused column —
/// the one containing today, or whichever the reader taps — is the accent step;
/// the rest sit in the de-emphasis step of the same ramp.
///
/// Anatomy: bars capped at 24px with a 4px rounded top and a square base on a
/// single baseline, solid hairline gridlines one step off the surface, exact
/// (never rounded) axis ticks, and one direct label on the focused column only.
/// Every column carries a full-height tap/focus target with the same readout, so
/// the tooltip never gates a value; the Expenses tab is the table view.
class TrendBarChart extends StatefulWidget {
  const TrendBarChart({
    super.key,
    required this.buckets,
    this.plotHeight = 164,
  });

  final List<TrendBucket> buckets;
  final double plotHeight;

  @override
  State<TrendBarChart> createState() => _TrendBarChartState();
}

class _TrendBarChartState extends State<TrendBarChart>
    with SingleTickerProviderStateMixin {
  static const double _axisWidth = 46;
  static const double _tickBand = 22;
  static const int _divisions = 2; // 3 gridlines: 0, mid, top

  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  int? _tapped;

  @override
  void initState() {
    super.initState();
    _grow.forward();
  }

  @override
  void didUpdateWidget(TrendBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(oldWidget.buckets) != _signature(widget.buckets)) {
      _tapped = null;
      _grow.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  String _signature(List<TrendBucket> buckets) =>
      buckets.map((b) => '${b.shortLabel}:${b.total}').join('|');

  /// Emphasis target: the reader's tap, else the current bucket, else the peak.
  int get _focusIndex {
    final buckets = widget.buckets;
    final tapped = _tapped;
    if (tapped != null && tapped < buckets.length) return tapped;
    final current = buckets.indexWhere((b) => b.isCurrent);
    if (current != -1) return current;
    var best = 0;
    for (var i = 1; i < buckets.length; i++) {
      if (buckets[i].total > buckets[best].total) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final buckets = widget.buckets;
    if (buckets.isEmpty) return const SizedBox.shrink();

    final peak = buckets.fold<double>(0, (m, b) => math.max(m, b.total));
    final axisTop = Analytics.niceCeiling(peak);
    final focus = _focusIndex;
    final focused = buckets[focus];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Readout: the value leads, the bucket name follows.
        Row(
          children: [
            Expanded(
              child: Text(
                focused.fullLabel,
                style: context.text.bodySmall?.copyWith(color: viz.inkMuted),
              ),
            ),
            Text(
              Money.format(focused.total),
              style: context.text.titleSmall?.copyWith(letterSpacing: -0.3),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _axisWidth,
              height: widget.plotHeight,
              child: _AxisTicks(
                axisTop: axisTop,
                divisions: _divisions,
                height: widget.plotHeight,
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: widget.plotHeight,
                    child: _Plot(
                      buckets: buckets,
                      axisTop: axisTop,
                      focus: focus,
                      grow: _grow,
                      onTap: (i) => setState(() => _tapped = i),
                    ),
                  ),
                  SizedBox(
                    height: _tickBand,
                    child: Row(
                      children: [
                        for (var i = 0; i < buckets.length; i++)
                          Expanded(
                            child: Center(
                              child: Text(
                                buckets[i].shortLabel,
                                maxLines: 1,
                                style: context.text.labelSmall?.copyWith(
                                  color: i == focus
                                      ? viz.inkPrimary
                                      : viz.inkMuted,
                                  fontWeight: i == focus
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Plot extends StatelessWidget {
  const _Plot({
    required this.buckets,
    required this.axisTop,
    required this.focus,
    required this.grow,
    required this.onTap,
  });

  final List<TrendBucket> buckets;
  final double axisTop;
  final int focus;
  final Animation<double> grow;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final n = buckets.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final slot = width / n;
        // Never fill the slot: the leftover is the surface gap that separates
        // neighbouring bars (well above the 2px minimum).
        final barWidth = math.min(24.0, math.max(7.0, slot - (n > 8 ? 7 : 14)));

        return AnimatedBuilder(
          animation: grow,
          builder: (context, _) {
            final progress = Curves.easeOutCubic.transform(grow.value);

            double barHeight(int i) {
              final value = buckets[i].total;
              if (value <= 0) return 0;
              final ratio = (value / axisTop).clamp(0.0, 1.0);
              // 3px floor so a very small spend is still visible and tappable.
              return math.max(3.0, ratio * height * progress);
            }

            final focusHeight = barHeight(focus);
            final labelBottom = math.min(focusHeight + 8, height - 16);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GridPainter(
                      divisions: _TrendBarChartState._divisions,
                      grid: viz.grid,
                      baseline: viz.baseline,
                    ),
                  ),
                ),
                for (var i = 0; i < n; i++)
                  Positioned(
                    left: slot * i + (slot - barWidth) / 2,
                    bottom: 0,
                    width: barWidth,
                    height: barHeight(i),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: i == focus ? viz.series : viz.seriesDeEmphasis,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                if (buckets[focus].total > 0)
                  Positioned(
                    left: (slot * focus + slot / 2 - 44).clamp(
                      0.0,
                      math.max(0.0, width - 88),
                    ),
                    width: 88,
                    bottom: labelBottom,
                    child: Center(
                      child: Text(
                        Money.compact(buckets[focus].total),
                        style: context.text.labelMedium?.copyWith(
                          color: viz.inkPrimary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                for (var i = 0; i < n; i++)
                  Positioned(
                    left: slot * i,
                    bottom: 0,
                    width: slot,
                    height: height,
                    child: Semantics(
                      button: true,
                      label:
                          '${buckets[i].fullLabel}, ${Money.format(buckets[i].total)}',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTap(i),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AxisTicks extends StatelessWidget {
  const _AxisTicks({
    required this.axisTop,
    required this.divisions,
    required this.height,
  });

  final double axisTop;
  final int divisions;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Stack(
      // The top tick is centred on the top gridline, so half of it sits above
      // the plot box and must not be clipped.
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i <= divisions; i++)
          Positioned(
            top: (height - 1) * i / divisions - 7,
            right: 8,
            child: Text(
              Money.axisTick(axisTop * (1 - i / divisions)),
              style: context.text.labelSmall?.copyWith(
                color: context.viz.inkMuted,
                fontSize: 10.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.divisions,
    required this.grid,
    required this.baseline,
  });

  final int divisions;
  final Color grid;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1;
    for (var i = 0; i <= divisions; i++) {
      final y = (size.height - 1) * i / divisions + 0.5;
      paint.color = i == divisions ? baseline : grid;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.divisions != divisions ||
      old.grid != grid ||
      old.baseline != baseline;
}
