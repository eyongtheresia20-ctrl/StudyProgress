import 'package:flutter/material.dart';
import '../widgets/app_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _rotationController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _rotationTurns;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim =
        CurvedAnimation(parent: _introController, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutBack),
    );
    _introController.forward();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..forward();

    _rotationTurns = Tween<double>(begin: 0.0, end: 3.0).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _introController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFAF9FE),
                  Color(0xFFF3EFFB),
                  Color(0xFFEDE7F8),
                ],
              ),
            ),
          ),
          Positioned(
            top: -90,
            right: -70,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFDE68A).withAlpha(90),
              ),
            ),
          ),
          Positioned(
            bottom: -110,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFDDD6FE).withAlpha(110),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: KivoraLogo(
                    size: 146,
                    showTitle: true,
                    lightText: false,
                    rotationTurns: _rotationTurns,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
