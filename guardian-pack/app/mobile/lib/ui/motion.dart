import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Entrance motion: fade + 12 px rise, staggered by [index]. Runs once when the
/// widget is first built; rebuilds don't replay it, so lists stay calm.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.stagger = const Duration(milliseconds: 40)});
  final Widget child;
  final int index;
  final Duration stagger;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final _curve = CurvedAnimation(parent: _c, curve: WpMotion.curve);

  @override
  void initState() {
    super.initState();
    final delay = widget.stagger * widget.index.clamp(0, 12);
    Future.delayed(delay, () { if (mounted) _c.forward(); });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(_curve),
          child: widget.child,
        ),
      );
}

/// Cross-fades (with a slight rise) whenever [switchKey] changes — used for tab
/// changes so the IndexedStack keeps every tab's state but the swap still moves.
class TabFade extends StatelessWidget {
  const TabFade({super.key, required this.switchKey, required this.child});
  final Object switchKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(switchKey),
        tween: Tween(begin: 0, end: 1),
        duration: WpMotion.base,
        curve: WpMotion.curve,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
        ),
        child: child,
      );
}

/// Number that counts to its new value instead of jumping (trip stats, battery).
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber(this.value, {super.key, required this.format, this.style});
  final double value;
  final String Function(double) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: value),
        duration: const Duration(milliseconds: 500),
        curve: WpMotion.curve,
        builder: (_, v, _) => Text(format(v), style: style),
      );
}

/// Press feedback for custom tappables: scales to 0.97 while held.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(scale: _down ? 0.97 : 1, duration: WpMotion.fast, curve: WpMotion.curve, child: widget.child),
      );
}
