import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// The one card shape used everywhere: surface fill, hairline ring, soft lift in
/// light mode only (a shadow on a near-black surface reads as mud).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSizes.cardPadding),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final hasHeader = title != null || trailing != null;

    return Container(
      decoration: BoxDecoration(
        color: viz.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: viz.hairline),
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
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasHeader) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(title!, style: context.text.titleSmall),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: context.text.bodySmall?.copyWith(
                            color: viz.inkMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSizes.gap),
          ],
          child,
        ],
      ),
    );
  }
}

/// Small text button used for card actions ("See all", "Show more").
class CardAction extends StatelessWidget {
  const CardAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Text(
              label,
              style: context.text.labelLarge?.copyWith(
                color: context.viz.series,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: context.viz.series,
            ),
          ],
        ),
      ),
    );
  }
}
