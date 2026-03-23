import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late Animation<Color?> _bgColor;

  late AnimationController _iconCtrl;
  late AnimationController _arvCtrl;
  late AnimationController _darwinCtrl;
  late AnimationController _tagCtrl;

  late Animation<double> _arvOpacity;
  late Animation<double> _arvSlide;
  late Animation<double> _darwinOpacity;
  late Animation<double> _darwinSlide;
  late Animation<double> _tagOpacity;
  late Animation<double> _tagSlide;

  @override
  void initState() {
    super.initState();

    // Fond blanc → noir — 800ms pour un fondu doux
    _bgCtrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _bgColor = ColorTween(
      begin: Colors.white,
      end: const Color(0xFF0A0A0A),
    ).animate(CurvedAnimation(parent: _bgCtrl, curve: Curves.easeIn));
    _bgCtrl.forward();

    // Icône — démarre à 900ms (fin du fade + petit délai)
    _iconCtrl = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _iconCtrl.forward();
    });

    // ARvision — 900 + 1500*0.75 = 2025ms
    _arvCtrl = AnimationController(
      duration: const Duration(milliseconds: 750),
      vsync: this,
    );
    _arvOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _arvCtrl, curve: Curves.easeInOut),
    );
    _arvSlide = Tween<double>(begin: -0.08, end: 0.0).animate(
      CurvedAnimation(parent: _arvCtrl, curve: Curves.easeInOut),
    );
    Future.delayed(const Duration(milliseconds: 2025), () {
      if (mounted) _arvCtrl.forward();
    });

    // Darwin Concept — 2025 + 480ms = 2505ms
    _darwinCtrl = AnimationController(
      duration: const Duration(milliseconds: 750),
      vsync: this,
    );
    _darwinOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _darwinCtrl, curve: Curves.easeInOut),
    );
    _darwinSlide = Tween<double>(begin: -0.08, end: 0.0).animate(
      CurvedAnimation(parent: _darwinCtrl, curve: Curves.easeInOut),
    );
    Future.delayed(const Duration(milliseconds: 2505), () {
      if (mounted) _darwinCtrl.forward();
    });

    // Tagline — 2505 + 480*2.25 = 3585ms
    _tagCtrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _tagOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _tagCtrl, curve: Curves.easeInOut),
    );
    _tagSlide = Tween<double>(begin: 6.0, end: 0.0).animate(
      CurvedAnimation(parent: _tagCtrl, curve: Curves.easeInOut),
    );
    Future.delayed(const Duration(milliseconds: 3585), () {
      if (mounted) _tagCtrl.forward();
    });

    // Navigation — 6000ms pour laisser le temps de lire la tagline
    Future.delayed(const Duration(milliseconds: 6000), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionDuration: const Duration(milliseconds: 600),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _iconCtrl.dispose();
    _arvCtrl.dispose();
    _darwinCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  double _spinScaleX(double raw) {
    final pos = raw * 2.0;
    final idx = pos.floor();
    final loc = pos - idx;
    final easedLoc = _eio(loc);
    final angle = (idx + easedLoc) * math.pi;
    return math.cos(angle);
  }

  double _eio(double t) => t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    // Logo limité à 50% de la largeur ET 50% de la hauteur
    // pour garder de l'espace en paysage
    final logoSize = (screenW * 0.5).clamp(0.0, screenH * 0.5);
    final logoLeft = (screenW - logoSize) / 2;
    final logoTop = (screenH - logoSize) / 2;
    final logoBottom = logoTop + logoSize;
    final tagY = logoBottom + (screenH - logoBottom) / 2;

    const iconAlignX = -0.732;
    const iconAlignY = -0.130;

    return AnimatedBuilder(
      animation: _bgCtrl,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _bgColor.value,
          body: Stack(
            children: [
              // Icône
              AnimatedBuilder(
                animation: _iconCtrl,
                builder: (context, _) {
                  final raw = _iconCtrl.value;
                  final sx = _spinScaleX(raw);
                  final opacity = (raw / 0.25).clamp(0.0, 1.0);
                  return Positioned(
                    left: logoLeft,
                    top: logoTop,
                    width: logoSize,
                    height: logoSize,
                    child: Opacity(
                      opacity: opacity,
                      child: Transform(
                        alignment: const Alignment(iconAlignX, iconAlignY),
                        transform: Matrix4.diagonal3Values(sx, 1.0, 1.0),
                        child: Image.asset(
                          'assets/images/icone.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },
              ),

              // ARvision
              AnimatedBuilder(
                animation: _arvCtrl,
                builder: (context, _) {
                  return Positioned(
                    left: logoLeft + _arvSlide.value * logoSize,
                    top: logoTop,
                    width: logoSize,
                    height: logoSize,
                    child: Opacity(
                      opacity: _arvOpacity.value,
                      child: Image.asset(
                        'assets/images/ar_vision.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),

              // Darwin Concept
              AnimatedBuilder(
                animation: _darwinCtrl,
                builder: (context, _) {
                  return Positioned(
                    left: logoLeft + _darwinSlide.value * logoSize,
                    top: logoTop,
                    width: logoSize,
                    height: logoSize,
                    child: Opacity(
                      opacity: _darwinOpacity.value,
                      child: Image.asset(
                        'assets/images/darwin_concept.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),

              // Tagline
              AnimatedBuilder(
                animation: _tagCtrl,
                builder: (context, _) {
                  return Positioned(
                    top: tagY - 10,
                    left: 0,
                    right: 0,
                    child: Opacity(
                      opacity: _tagOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, _tagSlide.value),
                        child: Center(
                          child: SizedBox(
                            width: screenW * 0.70,
                            child: const Text(
                              'AU-DELÀ DU PLAN',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFD2A0F0),
                                fontSize: 16,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 4.0,
                                fontStyle: FontStyle.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
