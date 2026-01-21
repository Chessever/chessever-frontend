import 'dart:async';
import 'dart:math' as math;
import 'package:app_settings/app_settings.dart';
import 'package:chessever2/services/review_prompt_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows a beautiful celebration overlay when user subscribes to premium.
/// Call this after a successful subscription purchase.
/// Pass [managementUrl] to show a "Manage subscription" button.
Future<void> showPremiumCelebration(BuildContext context, {String? managementUrl}) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _PremiumCelebrationOverlay(managementUrl: managementUrl);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    },
  );

  if (context.mounted) {
    unawaited(
      ReviewPromptService.instance.maybePrompt(
        context: context,
        trigger: ReviewPromptTrigger.premium,
      ),
    );
  }
}

class _PremiumCelebrationOverlay extends StatefulWidget {
  const _PremiumCelebrationOverlay({this.managementUrl});

  final String? managementUrl;

  @override
  State<_PremiumCelebrationOverlay> createState() =>
      _PremiumCelebrationOverlayState();
}

class _PremiumCelebrationOverlayState
    extends State<_PremiumCelebrationOverlay> with TickerProviderStateMixin {
  late AnimationController _confettiController;
  late AnimationController _glowController;
  final List<_ConfettiParticle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    // Generate confetti particles
    for (int i = 0; i < 50; i++) {
      _particles.add(_ConfettiParticle(
        x: _random.nextDouble(),
        y: -_random.nextDouble() * 0.3,
        size: 6 + _random.nextDouble() * 8,
        color: _confettiColors[_random.nextInt(_confettiColors.length)],
        rotationSpeed: (_random.nextDouble() - 0.5) * 10,
        fallSpeed: 0.3 + _random.nextDouble() * 0.5,
        swayAmplitude: 0.02 + _random.nextDouble() * 0.03,
        swaySpeed: 1 + _random.nextDouble() * 2,
        shape: _random.nextInt(3), // 0: circle, 1: square, 2: star
      ));
    }

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..forward();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Auto-dismiss after animation
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  static const _confettiColors = [
    Color(0xFFFFD700), // Gold
    Color(0xFFFFA500), // Orange
    Color(0xFF00CED1), // Dark Cyan
    Color(0xFF9370DB), // Medium Purple
    Color(0xFF00FF7F), // Spring Green
    Color(0xFFFF69B4), // Hot Pink
    kPrimaryColor,
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            // Confetti animation
            AnimatedBuilder(
              animation: _confettiController,
              builder: (context, child) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _ConfettiPainter(
                    particles: _particles,
                    progress: _confettiController.value,
                  ),
                );
              },
            ),

            // Central celebration content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glowing crown/premium icon
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      final glowIntensity = 0.3 + _glowController.value * 0.4;
                      return Container(
                        padding: EdgeInsets.all(24.sp),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              kPrimaryColor.withValues(alpha: glowIntensity),
                              Colors.transparent,
                            ],
                            stops: const [0.3, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: kPrimaryColor.withValues(alpha: glowIntensity * 0.8),
                              blurRadius: 40 + _glowController.value * 20,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: Container(
                      width: 100.w,
                      height: 100.h,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFFFFD700),
                            const Color(0xFFFFA500),
                            kPrimaryColor,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        size: 56.ic,
                        color: kBlackColor,
                      ),
                    ),
                  )
                      .animate()
                      .scale(
                        begin: const Offset(0.0, 0.0),
                        end: const Offset(1.0, 1.0),
                        duration: 600.ms,
                        curve: Curves.elasticOut,
                      ),

                  SizedBox(height: 32.h),

                  // Welcome text
                  Text(
                    'Welcome to Premium!',
                    style: AppTypography.displaySmBold.copyWith(
                      color: kWhiteColor,
                      fontSize: 28.f,
                      letterSpacing: -0.5,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 300.ms, duration: 400.ms)
                      .slideY(begin: 0.3, end: 0),

                  SizedBox(height: 12.h),

                  Text(
                    'You now have access to all features',
                    style: AppTypography.textMdMedium.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.7),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 500.ms, duration: 400.ms)
                      .slideY(begin: 0.3, end: 0),

                  SizedBox(height: 32.h),

                  // Manage subscription button
                  GestureDetector(
                    onTap: () async {
                      HapticFeedbackService.buttonPress();

                      final url = widget.managementUrl;
                      if (url != null && url.isNotEmpty) {
                        final uri = Uri.tryParse(url);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return;
                        }
                      }
                      await AppSettings.openAppSettings(type: AppSettingsType.subscriptions);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 20.sp, vertical: 12.sp),
                      decoration: BoxDecoration(
                        color: kWhiteColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.br),
                        border: Border.all(
                          color: kWhiteColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.settings_outlined,
                            color: kWhiteColor.withValues(alpha: 0.8),
                            size: 18.ic,
                          ),
                          SizedBox(width: 8.w),
                          Text(
                            'Manage subscription',
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 700.ms, duration: 400.ms)
                      .slideY(begin: 0.3, end: 0),

                  SizedBox(height: 32.h),

                  // Tap to continue hint
                  Text(
                    'Tap anywhere to continue',
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.4),
                    ),
                  )
                      .animate(onPlay: (controller) => controller.repeat(reverse: true))
                      .fadeIn(delay: 1500.ms, duration: 800.ms)
                      .then()
                      .fade(begin: 1.0, end: 0.5, duration: 800.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfettiParticle {
  double x;
  double y;
  final double size;
  final Color color;
  final double rotationSpeed;
  final double fallSpeed;
  final double swayAmplitude;
  final double swaySpeed;
  final int shape;
  double rotation = 0;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.color,
    required this.rotationSpeed,
    required this.fallSpeed,
    required this.swayAmplitude,
    required this.swaySpeed,
    required this.shape,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      // Update position based on progress
      final adjustedProgress = progress * particle.fallSpeed * 3;
      final currentY = particle.y + adjustedProgress * 1.5;

      // Sway side to side
      final sway = math.sin(progress * particle.swaySpeed * math.pi * 4) * particle.swayAmplitude;
      final currentX = particle.x + sway;

      // Skip if below screen
      if (currentY > 1.2) continue;

      final paint = Paint()
        ..color = particle.color.withValues(alpha: (1.0 - progress * 0.5).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      final offset = Offset(currentX * size.width, currentY * size.height);

      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(progress * particle.rotationSpeed);

      switch (particle.shape) {
        case 0: // Circle
          canvas.drawCircle(Offset.zero, particle.size / 2, paint);
          break;
        case 1: // Square
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: particle.size,
              height: particle.size,
            ),
            paint,
          );
          break;
        case 2: // Star shape (simplified as diamond)
          final path = Path();
          path.moveTo(0, -particle.size / 2);
          path.lineTo(particle.size / 3, 0);
          path.lineTo(0, particle.size / 2);
          path.lineTo(-particle.size / 3, 0);
          path.close();
          canvas.drawPath(path, paint);
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
