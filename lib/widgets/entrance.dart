import 'package:flutter/material.dart';

/// Drives one staggered entrance for a whole screen.
///
/// The stagger belongs to the screen, not the card: a card that is built later —
/// a lazy list item scrolled into view after the intro has finished — reads an
/// already-completed animation and appears immediately. A per-card timer would
/// leave such a card invisible until its own delay elapsed.
class ScreenIntro extends StatefulWidget {
  const ScreenIntro({super.key, required this.child});

  final Widget child;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_IntroScope>()?.animation;

  @override
  State<ScreenIntro> createState() => _ScreenIntroState();
}

class _ScreenIntroState extends State<ScreenIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _IntroScope(animation: _controller, child: widget.child);
}

class _IntroScope extends InheritedWidget {
  const _IntroScope({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_IntroScope oldWidget) =>
      oldWidget.animation != animation;
}

/// Fades and lifts its child into place, [index] steps behind the screen's
/// first card. Falls back to no animation when the platform asks for reduced
/// motion or when there is no [ScreenIntro] above it.
class Entrance extends StatelessWidget {
  const Entrance({super.key, this.index = 0, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final intro = ScreenIntro.maybeOf(context);
    if (intro == null || MediaQuery.disableAnimationsOf(context)) return child;

    final start = (index * 0.07).clamp(0.0, 0.55);
    final animation = CurvedAnimation(
      parent: intro,
      curve: Interval(
        start,
        (start + 0.45).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

/// Counts a money value up when it changes, so switching period reads as a
/// transition rather than a jump cut.
class AnimatedAmount extends StatelessWidget {
  const AnimatedAmount({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.duration = const Duration(milliseconds: 620),
  });

  final double value;
  final String Function(double) formatter;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(formatter(value), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) =>
          Text(formatter(animated), style: style),
    );
  }
}
