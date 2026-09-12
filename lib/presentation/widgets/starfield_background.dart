import 'dart:math';
import 'package:flutter/material.dart';

/// Fundo espacial estático (gradiente + estrelas), como no modelo de TV.
class StarfieldBackground extends StatelessWidget {
  final Widget child;

  const StarfieldBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0A1226),
            Color(0xFF0B1030),
            Color(0xFF090C10),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _StarPainter()),
          // Brilho suave da "nebulosa" central
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.1, 0.35),
                radius: 0.9,
                colors: [
                  const Color(0xFF3B2E6E).withValues(alpha: 0.35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7); // seed fixa: mesmo céu a cada frame
    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < 180; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.4 + rnd.nextDouble() * 1.3;
      paint.color = Colors.white.withValues(alpha: 0.25 + rnd.nextDouble() * 0.55);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
