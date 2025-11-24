import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:motor/motor.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Show a smooth sheet that mirrors the final onboarding auth upsell.
/// Returns `true` if the user ends up authenticated (non-anonymous) after closing.
Future<bool> showAuthUpgradeSheet({
  required BuildContext context,
}) async {
  final route = ChessSheetRoutes.preview(
    context: context,
    builder: (_) => _AuthUpgradeSheet(hostContext: context),
  );

  await Navigator.of(context).push(route);

  final user = Supabase.instance.client.auth.currentUser;
  return user != null && user.isAnonymous != true;
}

/// Thin guard used by protected actions to block guests.
Future<bool> requireFullAuthGuard(BuildContext context) async {
  final user = Supabase.instance.client.auth.currentUser;
  final isAuthenticated = user != null && user.isAnonymous != true;
  if (isAuthenticated) return true;

  return await showAuthUpgradeSheet(context: context);
}

class _AuthUpgradeSheet extends HookWidget {
  const _AuthUpgradeSheet({required this.hostContext});

  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator(
      onGenerateInitialRoutes: (_, __) => [
        SpringPagedSheetRoute(
          scrollConfiguration: const SheetScrollConfiguration(),
          dragConfiguration: ChessSheetConfigs.commentEditor,
          initialOffset: const SheetOffset.proportionalToViewport(0.9),
          snapGrid: SheetSnapGrid(
            snaps: const [
              SheetOffset.proportionalToViewport(0.7),
              SheetOffset.proportionalToViewport(0.95),
            ],
            minFlingSpeed: 600.0,
          ),
          builder: (_) => _AuthUpgradePage(hostContext: hostContext),
        ),
      ],
    );

    return SheetKeyboardDismissible(
      dismissBehavior:
          const DragDownSheetKeyboardDismissBehavior(isContentScrollAware: true),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(alpha: 0.97, borderRadius: 28.sp),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: navigator,
      ),
    );
  }
}

class _AuthUpgradePage extends HookWidget {
  const _AuthUpgradePage({required this.hostContext});

  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    Future<void> startAuthFlow() async {
      Navigator.of(hostContext).pop(); // Close sheet first
      // Use host context so navigation happens on app navigator
      Navigator.of(hostContext).pushNamed('/auth_screen');
    }

    return Stack(
      children: [
        const Positioned.fill(child: _AmbientGlow()),
        const Positioned.fill(child: _FloatingParticles()),
        MediaQuery.removePadding(
          context: context,
          removeBottom: true, // Let the sheet paint into the unsafe area
          child: Padding(
            padding: EdgeInsets.fromLTRB(24.w, topPadding + 28.h, 24.w, 20.h),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(Icons.close_rounded, color: kWhiteColor.withValues(alpha: 0.7)),
                      onPressed: () => Navigator.of(hostContext).pop(),
                    ),
                  ),
                  _UnlockVisual()
                      .animate()
                      .fadeIn(duration: 600.ms, curve: Motion.smoothSpring().toCurve)
                      .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
                  SizedBox(height: 24.h),
                  Text(
                    'Unlock the full\nexperience',
                    textAlign: TextAlign.center,
                    style: AppTypography.displayXsBold.copyWith(
                      color: kWhiteColor,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Create an account to access all features',
                    textAlign: TextAlign.center,
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.6),
                    ),
                  ),
                  SizedBox(height: 24.h),
                  _FeaturesList(),
                  SizedBox(height: 28.h),
                  _PrimaryButton(
                    label: 'Create free account',
                    onTap: startAuthFlow,
                  ),
                  SizedBox(height: 12.h),
                  _SecondaryButton(
                    label: 'Continue without account',
                    onTap: () => Navigator.of(hostContext).pop(),
                  ),
                  SizedBox(height: 14.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14.ic,
                        color: const Color(0xFFFFAA00).withValues(alpha: 0.7),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        'Guest data can\'t be recovered if lost',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnlockVisual extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final pulseController = useAnimationController(
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    final pulseAnimation = useAnimation(
      CurvedAnimation(parent: pulseController, curve: Curves.easeInOut),
    );

    return SizedBox(
      height: 140.h,
      width: 140.w,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: 1.0 + pulseAnimation * 0.08,
            child: Container(
              width: 130.w,
              height: 130.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kPrimaryColor.withValues(alpha: 0.2),
                    kPrimaryColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 100.w,
            height: 100.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kBlack2Color.withValues(alpha: 0.9),
              border: Border.all(
                color: kPrimaryColor.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: kPrimaryColor.withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.lock_open_rounded,
                size: 40.ic,
                color: kPrimaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final features = [
      _FeatureItem(
        icon: Icons.favorite_rounded,
        title: 'Save favorites',
        subtitle: 'Players, games & events',
        color: const Color(0xFFFF6B6B),
      ),
      _FeatureItem(
        icon: Icons.psychology_rounded,
        title: 'Analysis vault',
        subtitle: 'Store unlimited analyses',
        color: const Color(0xFF4ECDC4),
      ),
      _FeatureItem(
        icon: Icons.palette_rounded,
        title: 'Customization',
        subtitle: 'Board themes & pieces',
        color: const Color(0xFFFFE66D),
      ),
      _FeatureItem(
        icon: Icons.cloud_sync_rounded,
        title: 'Sync everywhere',
        subtitle: 'Access on any device',
        color: const Color(0xFF95E1D3),
      ),
    ];

    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.br),
        color: kBlack2Color.withValues(alpha: 0.5),
        border: Border.all(
          color: kWhiteColor.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          Text(
            'What you\'ll miss as a guest:',
            style: AppTypography.textXsMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 16.h),
          ...features.asMap().entries.map((entry) {
            final index = entry.key;
            final feature = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: index < features.length - 1 ? 12.h : 0),
              child: feature,
            );
          }),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40.w,
          height: 40.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.br),
            color: color.withValues(alpha: 0.15),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 20.ic,
              color: color,
            ),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor,
                ),
              ),
              Text(
                subtitle,
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.lock_outline_rounded,
          size: 16.ic,
          color: kWhiteColor.withValues(alpha: 0.25),
        ),
      ],
    );
  }
}

class _PrimaryButton extends HookWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);

    return GestureDetector(
      onTapDown: (_) => isPressed.value = true,
      onTapUp: (_) {
        isPressed.value = false;
        if (!isLoading) onTap();
      },
      onTapCancel: () => isPressed.value = false,
      child: AnimatedScale(
        scale: isPressed.value ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: 52.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.br),
            gradient: const LinearGradient(
              colors: [Color(0xFF3BC4FF), Color(0xFF5E61FF)],
            ),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 18.w,
                    height: 18.h,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    label,
                    style: AppTypography.textMdMedium.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends HookWidget {
  const _SecondaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);

    return GestureDetector(
      onTapDown: (_) => isPressed.value = true,
      onTapUp: (_) {
        isPressed.value = false;
        onTap();
      },
      onTapCancel: () => isPressed.value = false,
      child: AnimatedScale(
        scale: isPressed.value ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: 52.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.br),
            border: Border.all(
              color: kWhiteColor.withValues(alpha: 0.15),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmbientGlow extends HookWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    final animation = useAnimation(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );

    return CustomPaint(
      painter: _AmbientGlowPainter(animation),
      size: Size.infinite,
    );
  }
}

class _AmbientGlowPainter extends CustomPainter {
  _AmbientGlowPainter(this.animation);
  final double animation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = kPrimaryColor.withValues(alpha: 0.08 + (animation * 0.04))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 120);

    canvas.drawCircle(
      Offset(
        size.width * (0.3 + animation * 0.1),
        size.height * (0.25 + animation * 0.05),
      ),
      size.width * 0.4,
      paint1,
    );

    final paint2 = Paint()
      ..color = const Color(0xFF08647F).withValues(alpha: 0.06 + (animation * 0.03))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    canvas.drawCircle(
      Offset(
        size.width * (0.7 - animation * 0.1),
        size.height * (0.7 - animation * 0.05),
      ),
      size.width * 0.35,
      paint2,
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientGlowPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class _FloatingParticles extends HookWidget {
  const _FloatingParticles();

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(seconds: 20),
    )..repeat();

    final animation = useAnimation(controller);

    return CustomPaint(
      painter: _ParticlePainter(animation),
      size: Size.infinite,
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.animation);
  final double animation;

  static final List<_Particle> particles = List.generate(
    12,
    (i) => _Particle(
      x: (i * 0.083) + 0.05,
      y: (i % 3) * 0.3 + 0.1,
      size: 2.0 + (i % 3) * 1.5,
      speed: 0.3 + (i % 4) * 0.15,
      opacity: 0.15 + (i % 3) * 0.1,
    ),
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final y = ((particle.y + animation * particle.speed) % 1.2) - 0.1;
      final x = particle.x + math.sin(animation * 2 * math.pi + particle.x * 10) * 0.02;

      final paint = Paint()
        ..color = kWhiteColor.withValues(alpha: particle.opacity * (1 - y.abs() * 0.5));

      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });

  final double x, y, size, speed, opacity;
}
