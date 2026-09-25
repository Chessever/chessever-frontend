import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// A soft cyan blob behind the auth hero. It reads as light on the dark
/// stage; on paper it is a background glow smudge, so light draws nothing.
class BlurBackground extends StatelessWidget {
  const BlurBackground({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.isLightTheme) return const SizedBox.expand();
    return RepaintBoundary(
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

class AnimatedBlurBackground extends HookWidget {
  const AnimatedBlurBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final animationController = useAnimationController(
      duration: Duration(seconds: 1),
    );

    animationController.forward();
    animationController.repeat();

    final fadeAnimation = useAnimation(
      CurvedAnimation(parent: animationController, curve: Curves.bounceInOut),
    );

    if (context.isLightTheme) return const SizedBox.expand();
    return AnimatedOpacity(
      opacity: fadeAnimation,
      duration: Duration(seconds: 1),
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(
            MediaQuery.of(context).size.width,
            MediaQuery.of(context).size.height,
          ),
          painter: BlurPainter(context),
        ),
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
          ..color = const Color(0xFF0FB4E5).withAlpha(
            150,
          ) // Changed to black with opacity
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            100,
          ); // Reduced blur radius

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
