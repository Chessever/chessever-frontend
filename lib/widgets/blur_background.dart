import 'package:flutter/material.dart';

class BlurBackground extends StatelessWidget {
  const BlurBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(393, 700),
      painter: BlurPainter(),
    );
  }
}

class BlurPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF0FB4E5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 150);

    // Left circle
    canvas.drawCircle(
      Offset(149, 350),
      50,
      paint,
    );

    // Right circle
    canvas.drawCircle(
      Offset(245, 350),
      50,
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

