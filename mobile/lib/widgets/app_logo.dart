import 'package:flutter/material.dart';

class KivoraLogo extends StatelessWidget {
  final double size;
  final bool showTitle;
  final bool lightText;
  final Animation<double>? rotationTurns;

  const KivoraLogo({
    super.key,
    this.size = 84,
    this.showTitle = false,
    this.lightText = false,
    this.rotationTurns,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        lightText ? Colors.white : const Color(0xFF1E105A);
    final subColor =
        lightText ? const Color(0xFFFDE68A) : const Color(0xFF9A6B16);

    Widget emblem = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFFEAB308).withAlpha(140),
          width: size * 0.025,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF26145E).withAlpha(28),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: ClipOval(
        child: Transform.scale(
          scale: 1.18,
          child: Image.asset(
            'assets/images/kivora_logo.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(
                Icons.menu_book_rounded,
                color: Color(0xFF26145E),
              ),
            ),
          ),
        ),
      ),
    );

    if (rotationTurns != null) {
      emblem = RotationTransition(
        turns: rotationTurns!,
        child: emblem,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        emblem,
        if (showTitle) ...[
          SizedBox(height: size * 0.16),
          Text(
            'Kivora',
            style: TextStyle(
              fontSize: size * 0.30,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Learn. Grow. Become.',
            style: TextStyle(
              fontSize: size * 0.135,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: subColor,
            ),
          ),
        ],
      ],
    );
  }
}
