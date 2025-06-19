import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class BlurBackground extends StatelessWidget {
  const BlurBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(
        MediaQuery.of(context).size.width,
        MediaQuery.of(context).size.height,
      ),
      painter: BlurPainter(context),
    );
  }
}

class AnimatedBlurBackground extends HookWidget {
  const AnimatedBlurBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final animationController = useAnimationController(
      duration: Duration(seconds: 1),
    );

    animationController.forward();


    final fadeAnimation = useAnimation(
      CurvedAnimation(parent: animationController, curve: Curves.easeInOut),
    );

    return AnimatedOpacity(
      opacity: fadeAnimation,
      duration: Duration(seconds: 1),
      child: CustomPaint(
        size: Size(
          MediaQuery.of(context).size.width,
          MediaQuery.of(context).size.height,
        ),
        painter: BlurPainter(context),
      ),
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
