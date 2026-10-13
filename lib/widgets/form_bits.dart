import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'pressable.dart';

/// Small caps label above a form field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: context.text.labelSmall?.copyWith(
        color: context.viz.inkMuted,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// A tappable choice in a form: a preset, a date, a kind. Selected state is
/// shown by fill and ring, never colour alone — the label carries the meaning.
class PickChip extends StatelessWidget {
  const PickChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final ink = selected ? viz.series : viz.inkSecondary;
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? viz.series.withValues(alpha: context.isDarkMode ? 0.24 : 0.12)
              : viz.surfaceAlt,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: selected ? viz.series : viz.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: ink),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelLarge?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The error line under a form, in words beside an icon.
class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 15, color: viz.critical),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: context.text.bodySmall?.copyWith(color: viz.critical),
          ),
        ),
      ],
    );
  }
}

/// The full-width primary button at the foot of a sheet, with a spinner while
/// the save is in flight.
class SheetSaveButton extends StatelessWidget {
  const SheetSaveButton({
    super.key,
    required this.label,
    required this.saving,
    required this.onPressed,
  });

  final String label;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: saving ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: viz.series,
          foregroundColor: Colors.white,
          disabledBackgroundColor: viz.series.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: context.text.titleSmall?.copyWith(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }
}
