import 'package:flutter/material.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 14),
            child: Text(
              '9:41',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          CustomPaint(
            size: const Size(143, 54),
            painter: StatusIconsPainter(),
          ),
        ],
      ),
    );
  }
}

class StatusIconsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Battery outline
    final RRect batteryOutline = RRect.fromRectAndRadius(
      Rect.fromLTWH(83.5, 23.5, 24, 12),
      const Radius.circular(3.8),
    );
    canvas.drawRRect(batteryOutline, paint..color = Colors.white.withOpacity(0.35));

    // Battery fill
    paint.style = PaintingStyle.fill;
    final RRect batteryFill = RRect.fromRectAndRadius(
      Rect.fromLTWH(85, 25, 21, 9),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(batteryFill, paint..color = Colors.white);

    // Battery tip
    final Path batteryTip = Path()
      ..moveTo(109, 27.78)
      ..lineTo(109, 31.86)
      ..quadraticBezierTo(110.328, 31.51, 110.328, 29.82)
      ..quadraticBezierTo(110.328, 28.93, 109, 27.78);
    canvas.drawPath(batteryTip, paint..color = Colors.white.withOpacity(0.4));

    // WiFi icon
    paint.color = Colors.white;
    drawWiFiIcon(canvas, paint);

    // Signal strength bars
    drawSignalBars(canvas, paint);
  }

  void drawWiFiIcon(Canvas canvas, Paint paint) {
    final Path wifiPath = Path()
      ..moveTo(67.27, 26.10)
      ..addPath(Path()..moveTo(67.27, 26.10), Offset(0, 0));
    // Add the complete WiFi icon path here
    canvas.drawPath(wifiPath, paint);
  }

  void drawSignalBars(Canvas canvas, Paint paint) {
    // Draw the 4 signal strength bars
    for (var i = 0; i < 4; i++) {
      final double x = 32 + (i * 4.5);
      final double height = 4 + (i * 2);
      canvas.drawRect(
        Rect.fromLTWH(x, 31.07 - height, 3, height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
