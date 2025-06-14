import 'package:flutter/material.dart';

class BlurBackground extends StatelessWidget {
  const BlurBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(393, 700),
      painter: BlurPainter(context),
    );
  }
}

class BlurPainter extends CustomPainter {
  BlurPainter(this.context);

  final BuildContext context;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..color = const Color(0xFF0FB4E5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    // Left circle
    canvas.drawCircle(
      Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      ),
      70,
      paint,
    );

    // Right circle
    canvas.drawCircle(
      Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      ),
      70,
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
