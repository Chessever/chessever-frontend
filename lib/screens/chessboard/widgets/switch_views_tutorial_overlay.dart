import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Canonical SharedPreferences keys for the "Switch Views" walkthrough.
/// Shared between the standalone gamebase explorer screen and the
/// chess board screen's step-2 tutorial so users aren't re-taught the
/// same gesture twice.
const String kSwitchViewsWalkthroughShownDateKey =
    'explorer_panel_walkthrough_shown_date';
const String kSwitchViewsWalkthroughDontShowKey =
    'explorer_panel_walkthrough_dont_show';

/// Full-screen teaching overlay that shows a hand swiping horizontally,
/// a card with the "Switch Views" copy, and a pulsing Explorer / Notation
/// hint. Designed to be inserted via `Overlay.of(context, rootOverlay: true)`
/// so it sits above the surrounding route. The animations are driven by
/// the caller so the overlay stays in sync with the underlying PageView
/// (both the hand position and the page offset share the same clock).
class SwitchViewsTutorialOverlay extends StatefulWidget {
  const SwitchViewsTutorialOverlay({
    super.key,
    required this.onDismiss,
    required this.onDontShowAgain,
    required this.animationController,
    required this.moveAnimation,
    required this.fadeAnimation,
    required this.scaleAnimation,
    required this.currentPageIndex,
    required this.totalItems,
    this.currentStep,
    this.totalSteps,
  });

  final VoidCallback onDismiss;
  final VoidCallback onDontShowAgain;
  final AnimationController animationController;
  final Animation<double> moveAnimation;
  final Animation<double> fadeAnimation;
  final Animation<double> scaleAnimation;
  final int currentPageIndex;
  final int totalItems;

  /// When both [currentStep] and [totalSteps] are provided and
  /// [totalSteps] > 1, a small step-indicator row is rendered above the
  /// title so chained tutorials can show progress (e.g. "Step 2 of 2").
  final int? currentStep;
  final int? totalSteps;

  @override
  State<SwitchViewsTutorialOverlay> createState() =>
      _SwitchViewsTutorialOverlayState();
}

class _SwitchViewsTutorialOverlayState extends State<SwitchViewsTutorialOverlay>
    with SingleTickerProviderStateMixin {
  double _opacityTarget = 0.0;
  bool _isExiting = false;
  late AnimationController _timerController;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _opacityTarget = 1.0;
      });
      _timerController.forward();
    });

    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animateOut();
      }
    });
  }

  @override
  void dispose() {
    _timerController.dispose();
    super.dispose();
  }

  Future<void> _animateOut() async {
    if (_isExiting) return;
    _timerController.stop();
    setState(() {
      _isExiting = true;
      _opacityTarget = 0.0;
    });
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) widget.onDismiss();
  }

  Future<void> _handleDontShowAgain() async {
    if (_isExiting) return;
    _timerController.stop();
    setState(() {
      _isExiting = true;
      _opacityTarget = 0.0;
    });
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) widget.onDontShowAgain();
  }

  @override
  Widget build(BuildContext context) {
    final totalSteps = widget.totalSteps ?? 0;
    final currentStep = widget.currentStep ?? 0;
    final showStepIndicator = totalSteps > 1 && currentStep > 0;

    return SingleMotionBuilder(
      motion: const CupertinoMotion.snappy(),
      value: _opacityTarget,
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              onTap: _animateOut,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: MediaQuery.sizeOf(context).height,
                width: MediaQuery.sizeOf(context).width,
                color: kBlackColor.withValues(alpha: 0.8),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: 80.h),
                      SizedBox(
                        width: 280.w,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.topCenter,
                          children: [
                            AnimatedBuilder(
                              animation: _timerController,
                              builder: (context, _) {
                                return CustomPaint(
                                  foregroundPainter: _BorderProgressPainter(
                                    progress: _timerController.value,
                                    color: kPrimaryColor,
                                    strokeWidth: 3.0,
                                    borderRadius: 28.br,
                                  ),
                                  child: Container(
                                    padding: EdgeInsets.fromLTRB(
                                      24.w,
                                      36.h,
                                      24.w,
                                      24.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.colors.textPrimary,
                                      borderRadius: BorderRadius.circular(
                                        28.br,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 30,
                                          offset: const Offset(0, 12),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (showStepIndicator) ...[
                                          TutorialStepIndicator(
                                            currentStep: currentStep,
                                            totalSteps: totalSteps,
                                          ),
                                          SizedBox(height: 10.h),
                                        ],
                                        Text(
                                          'Switch Views',
                                          style: AppTypography.textLgBold
                                              .copyWith(
                                                color: kBlackColor,
                                                height: 1.2,
                                                letterSpacing: -0.5,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(height: 8.h),
                                        Text(
                                          'Swipe between views, or tap Explorer / Notation in the title bar.',
                                          style: AppTypography.textSmMedium
                                              .copyWith(
                                                color: kBlackColor.withValues(
                                                  alpha: 0.6,
                                                ),
                                                height: 1.4,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(height: 16.h),
                                        const _TapTitleHint(),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            Positioned(
                              top: -20.h,
                              child: Container(
                                padding: EdgeInsets.all(10.sp),
                                decoration: BoxDecoration(
                                  color: kPrimaryColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPrimaryColor.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: context.colors.textPrimary,
                                    width: 3,
                                  ),
                                ),
                                child: Icon(
                                  Icons.swap_horiz_rounded,
                                  color: context.colors.textPrimary,
                                  size: 22.sp,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 120.h,
                        width: double.infinity,
                        child: AnimatedBuilder(
                          animation: widget.animationController,
                          builder: (context, _) {
                            if (!widget.animationController.isAnimating) {
                              return const SizedBox.shrink();
                            }
                            final width = MediaQuery.sizeOf(context).width;
                            final canGoNext =
                                widget.currentPageIndex < widget.totalItems - 1;
                            final direction = canGoNext ? 1.0 : -1.0;
                            final maxDrag = width * 0.5;
                            final handTranslation =
                                -1 *
                                widget.moveAnimation.value *
                                maxDrag *
                                direction;

                            return Opacity(
                              opacity: widget.fadeAnimation.value,
                              child: Transform.translate(
                                offset: Offset(handTranslation, 0),
                                child: Transform.scale(
                                  scale: widget.scaleAnimation.value,
                                  child: Center(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: context.colors.textPrimary.withValues(
                                          alpha: 0.15,
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.3,
                                            ),
                                            blurRadius: 20,
                                            spreadRadius: 5,
                                          ),
                                        ],
                                      ),
                                      padding: EdgeInsets.all(24.sp),
                                      child: Icon(
                                        Icons.touch_app_rounded,
                                        size: 52.sp,
                                        color: context.colors.textPrimary,
                                        shadows: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.5,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 24.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _handleDontShowAgain,
                            style: TextButton.styleFrom(
                              foregroundColor: context.colors.textPrimary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            child: Text(
                              "Don't show again",
                              style: AppTypography.textSmMedium,
                            ),
                          ),
                          SizedBox(width: 24.w),
                          TextButton(
                            onPressed: _animateOut,
                            style: TextButton.styleFrom(
                              foregroundColor: context.colors.textPrimary,
                              backgroundColor: context.colors.textPrimary.withValues(
                                alpha: 0.1,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: 24.w,
                                vertical: 12.h,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30.br),
                              ),
                            ),
                            child: Text(
                              'Got it',
                              style: AppTypography.textSmBold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 32.h),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Small "● ○" progress row used by chained tutorials. Rendered inside
/// the white card so the step count sits right on top of the title.
class TutorialStepIndicator extends StatelessWidget {
  const TutorialStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalSteps, (index) {
        final isActive = index + 1 == currentStep;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 3.w),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: isActive ? 18.w : 6.w,
            height: 6.h,
            decoration: BoxDecoration(
              color:
                  isActive
                      ? kPrimaryColor
                      : kBlackColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999.br),
            ),
          ),
        );
      }),
    );
  }
}

class _BorderProgressPainter extends CustomPainter {
  _BorderProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.borderRadius,
  });

  final double progress;
  final Color color;
  final double strokeWidth;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final r = borderRadius;
    final topCenter = w / 2;
    final bottomCenter = w / 2;

    final rightPath =
        Path()
          ..moveTo(topCenter, 0)
          ..lineTo(w - r, 0)
          ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
          ..lineTo(w, h - r)
          ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
          ..lineTo(bottomCenter, h);

    final leftPath =
        Path()
          ..moveTo(topCenter, 0)
          ..lineTo(r, 0)
          ..arcToPoint(
            Offset(0, r),
            radius: Radius.circular(r),
            clockwise: false,
          )
          ..lineTo(0, h - r)
          ..arcToPoint(
            Offset(r, h),
            radius: Radius.circular(r),
            clockwise: false,
          )
          ..lineTo(bottomCenter, h);

    final rightMetric = rightPath.computeMetrics().first;
    canvas.drawPath(
      rightMetric.extractPath(0, rightMetric.length * progress),
      paint,
    );

    final leftMetric = leftPath.computeMetrics().first;
    canvas.drawPath(
      leftMetric.extractPath(0, leftMetric.length * progress),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BorderProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.borderRadius != borderRadius;
  }
}

class _TapTitleHint extends StatefulWidget {
  const _TapTitleHint();

  @override
  State<_TapTitleHint> createState() => _TapTitleHintState();
}

class _TapTitleHintState extends State<_TapTitleHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value;
        final tapOnLeft = phase < 0.5;
        final localProgress = (tapOnLeft ? phase : phase - 0.5) * 2;
        final pulse =
            localProgress < 0.35
                ? localProgress / 0.35
                : (1 - (localProgress - 0.35) / 0.65).clamp(0.0, 1.0);

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14.br),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TapTitleSegment(
                label: 'Explorer',
                isActive: tapOnLeft,
                pulseStrength: tapOnLeft ? pulse : 0,
              ),
              SizedBox(width: 8.w),
              _TapTitleDot(isSelected: tapOnLeft),
              SizedBox(width: 4.w),
              _TapTitleDot(isSelected: !tapOnLeft),
              SizedBox(width: 8.w),
              _TapTitleSegment(
                label: 'Notation',
                isActive: !tapOnLeft,
                pulseStrength: !tapOnLeft ? pulse : 0,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TapTitleSegment extends StatelessWidget {
  const _TapTitleSegment({
    required this.label,
    required this.isActive,
    required this.pulseStrength,
  });

  final String label;
  final bool isActive;
  final double pulseStrength;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (pulseStrength > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Container(
                  width: 36.sp + pulseStrength * 18,
                  height: 24.sp + pulseStrength * 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.circular(20.br),
                    color: kPrimaryColor.withValues(
                      alpha: (1 - pulseStrength) * 0.45,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Text(
          label,
          style: TextStyle(
            color:
                isActive
                    ? context.colors.textPrimary
                    : context.colors.textSecondary.withValues(alpha: 0.7),
            fontSize: 13.f,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _TapTitleDot extends StatelessWidget {
  const _TapTitleDot({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5.sp,
      height: 5.sp,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            isSelected
                ? context.colors.textPrimary
                : context.colors.textSecondary.withValues(alpha: 0.4),
      ),
    );
  }
}
