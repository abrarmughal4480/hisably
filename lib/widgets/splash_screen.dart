import 'package:flutter/material.dart';

import '../theme/hisably_theme.dart';
import 'logo.dart';

/// Animated launch splash (v0.6.8) — the way pro apps open: the logo
/// scales and fades in with a soft overshoot, the wordmark and tagline
/// rise beneath it, and a thin gradient line grows as the progress cue.
/// Purely presentational; the app swaps it out once loading finishes
/// and the minimum display time has passed.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.tagline});
  final String tagline;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoScale = Tween(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: const Interval(0, 0.55, curve: Curves.easeOutBack)));
    final logoFade = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: const Interval(0, 0.4)));
    final textFade = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: const Interval(0.35, 0.85)));
    final textRise = Tween(begin: 14.0, end: 0.0).animate(
        CurvedAnimation(parent: _c, curve: const Interval(0.35, 0.85, curve: Curves.easeOut)));
    final lineGrow = Tween(begin: 0.0, end: 120.0).animate(
        CurvedAnimation(parent: _c, curve: const Interval(0.25, 1.0, curve: Curves.easeInOut)));

    return Scaffold(
      backgroundColor: HisablyColors.background,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: logoFade.value,
                child: Transform.scale(
                  scale: logoScale.value,
                  child: const HisablyLogo(size: 96),
                ),
              ),
              const SizedBox(height: 22),
              Opacity(
                opacity: textFade.value,
                child: Transform.translate(
                  offset: Offset(0, textRise.value),
                  child: Column(
                    children: [
                      const Text('Hisably',
                          style: TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: HisablyColors.text,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Text(widget.tagline,
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13.5,
                              color: HisablyColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Container(
                width: lineGrow.value,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(colors: [
                    Color(0xFF4ADE80),
                    HisablyColors.logoGreenDeep,
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
