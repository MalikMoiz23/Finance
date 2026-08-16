import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// One row's share of a total. The track is a lighter step of the fill's own
/// ramp, so the meter reads across its whole length.
///
/// Magnitude only — a single hue, never a category identity colour.
class ShareMeter extends StatelessWidget {
  const ShareMeter({super.key, required this.share, this.height = 7});

  final double share;
  final double height;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final radius = height / 2 + 0.5;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        height: height,
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
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
