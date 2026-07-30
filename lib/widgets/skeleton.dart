import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// A shimmering placeholder block. Loading states hold the shape of the content
/// that is coming, so nothing jumps when the data lands.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 7});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final base = viz.surfaceAlt;
    final highlight = context.isDarkMode
        ? viz.inkPrimary.withValues(alpha: 0.06)
        : viz.inkPrimary.withValues(alpha: 0.04);

    final box = SizedBox(width: widget.width, height: widget.height);

    if (MediaQuery.disableAnimationsOf(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: box,
      );
    }

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        // Sweep the highlight left to right, twice as wide as the block so the
        // gradient never sits still.
        final t = _shimmer.value * 2 - 0.5;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 0.6, 0),
              end: Alignment(t + 0.6, 0),
              colors: [base, highlight, base],
              stops: const [0.15, 0.5, 0.85],
            ),
          ),
          child: box,
        );
      },
    );
  }
}

/// Placeholder shaped like the trend chart: an axis of bars of varying height.
class ChartSkeleton extends StatelessWidget {
  const ChartSkeleton({super.key, this.bars = 5, this.height = 150});

  final int bars;
  final double height;

  @override
  Widget build(BuildContext context) {
    const heights = [0.35, 0.7, 0.5, 0.9, 0.45, 0.65, 0.3, 0.8];
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < bars; i++)
            Skeleton(
              width: 22,
              height: height * heights[i % heights.length],
              radius: 5,
            ),
        ],
      ),
    );
  }
}

/// Placeholder shaped like a row of the category breakdown or the expense list.
class RowsSkeleton extends StatelessWidget {
  const RowsSkeleton({super.key, this.rows = 3, this.withMeter = true});

  final int rows;
  final bool withMeter;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          Row(
            children: [
              const Skeleton(width: 40, height: 40, radius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Skeleton(width: 90 + i * 18, height: 13),
                        const Spacer(),
                        const Skeleton(width: 62, height: 13),
                      ],
                    ),
                    if (withMeter) ...[
                      const SizedBox(height: 9),
                      const Skeleton(height: 7, radius: 4),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
