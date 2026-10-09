import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'widgets.dart';

/// Navy splash with the wordmark slowly "breathing" (opacity + scale) while
/// Firebase / auth come up. Loops until replaced.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.message});
  final String? message;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  late final _curve = CurvedAnimation(parent: _c, curve: Curves.easeInOutSine);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WpColors.navy,
      body: Center(
        child: AnimatedBuilder(
          animation: _curve,
          builder: (_, child) => Opacity(
            opacity: 0.55 + 0.45 * _curve.value,
            child: Transform.scale(scale: 0.96 + 0.04 * _curve.value, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Wordmark(size: 36),
              if (widget.message != null) ...[
                const SizedBox(height: WpSpace.m),
                Text(widget.message!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton of the Map tab, shown while the profile and device load so the first
/// frame already has the app's shape instead of a blank screen.
class ShellSkeleton extends StatelessWidget {
  const ShellSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Scaffold(
      appBar: const WpHeader(),
      body: Stack(children: [
        Positioned.fill(child: Shimmer(child: Container(color: wp.line))),
        Positioned(
          left: WpSpace.l,
          right: WpSpace.l,
          bottom: WpSpace.l,
          child: WpCard(
            padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.m, WpSpace.l, WpSpace.m),
            child: const Shimmer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 160),
                  SizedBox(height: WpSpace.m),
                  Skeleton(width: 220, height: 20),
                  SizedBox(height: WpSpace.s),
                  Skeleton(width: 120),
                  SizedBox(height: WpSpace.xl),
                  Skeleton(height: 44),
                ],
              ),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: SizedBox(width: 24, height: 24), label: 'Map Pin'),
          NavigationDestination(icon: SizedBox(width: 24, height: 24), label: 'Trip History'),
          NavigationDestination(icon: SizedBox(width: 24, height: 24), label: 'Notification'),
          NavigationDestination(icon: SizedBox(width: 24, height: 24), label: 'Settings'),
        ],
      ),
    );
  }
}

/// Soft opacity sweep over skeleton blocks — the one loading motion in the app.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: widget.child,
      );
}
