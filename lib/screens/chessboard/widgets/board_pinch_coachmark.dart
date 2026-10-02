import 'package:chessever2/screens/chessboard/widgets/switch_views_tutorial_overlay.dart'
    show TutorialStepIndicator;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Canonical SharedPreferences key for the "Pinch to resize" walkthrough —
/// the second step of the chained chess-board teaching flow (after "Swipe to
/// Browse"). Kept here beside the overlay so every caller gates on one name.
const String kPinchWalkthroughShownKey = 'board_pinch_coachmark_seen';
const String kPinchWalkthroughDontShowKey = 'board_pinch_coachmark_dont_show';

/// Full-screen teaching overlay explaining pinch-to-resize, in the exact same
/// card format as the "Swipe to Browse" overlay: a white card with a
/// timer-progress border, optional step dots, a floating icon badge, and
/// Don't-show-again / Got-it actions over a dim scrim. Self-contained — it
/// drives its own two-finger pinch demo — so it can be dropped straight into
/// `Overlay.of(context, rootOverlay: true)`.
class BoardPinchCoachmark extends StatefulWidget {
  const BoardPinchCoachmark({
    super.key,
    required this.onDismiss,
    required this.onDontShowAgain,
    this.currentStep,
    this.totalSteps,
  });

  final VoidCallback onDismiss;
  final VoidCallback onDontShowAgain;

  /// When both are provided and [totalSteps] > 1, a step-indicator row renders
  /// above the title so the chained flow shows progress (e.g. "Step 2 of 2").
  final int? currentStep;
  final int? totalSteps;

  @override
  State<BoardPinchCoachmark> createState() => _BoardPinchCoachmarkState();
}

class _BoardPinchCoachmarkState extends State<BoardPinchCoachmark>
    with TickerProviderStateMixin {
  double _opacityTarget = 0.0;
  bool _isExiting = false;

  /// 8s auto-dismiss timer that also paints the progress border.
  late AnimationController _timerController;

  /// Loops the two-finger pinch demo independently of the timer.
  late AnimationController _handController;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _handController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _opacityTarget = 1.0);
      _timerController.forward();
    });

    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _animateOut();
    });
  }

  @override
  void dispose() {
    _timerController.dispose();
    _handController.dispose();
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
                                  foregroundPainter:
                                      _PinchBorderProgressPainter(
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
                                      // White surface + black text stays legible
                                      // on the dim scrim in both themes — matches
                                      // the other teaching cards.
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(28.br),
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
                                          'Pinch to Resize',
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
                                          'Move two fingers together or apart '
                                          'on the board to resize it to your '
                                          'liking.',
                                          style: AppTypography.textSmMedium
                                              .copyWith(
                                                color: kBlackColor.withValues(
                                                  alpha: 0.6,
                                                ),
                                                height: 1.4,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
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
                                  boxShadow: context.isLightTheme
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: kPrimaryColor.withValues(
                                              alpha: 0.4,
                                            ),
                                            blurRadius: 12,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                ),
                                child: Icon(
                                  Icons.pinch_rounded,
                                  // Paper: accent ink (white on cyan is 2.4:1).
                                  color: context.isLightTheme
                                      ? context.colors.inkOnAccent
                                      : Colors.white,
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
                          animation: _handController,
                          builder: (context, _) {
                            return _PinchFingersDemo(
                              progress: _handController.value,
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
                              foregroundColor: Colors.white.withValues(
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
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white.withValues(
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

/// Looping demo: two fingers spread apart and come back together — the visual
/// analogue of the swipe hand in the other teaching overlays.
class _PinchFingersDemo extends StatelessWidget {
  const _PinchFingersDemo({required this.progress});

  /// 0→1→0 from the parent's repeating (reverse) controller.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final travel = 46.sp * Curves.easeInOut.transform(progress);

    Widget finger(double angle) => Transform.rotate(
      angle: angle,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        padding: EdgeInsets.all(16.sp),
        child: Icon(
          Icons.touch_app_rounded,
          size: 44.sp,
          color: Colors.white,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
    );

    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: Offset(-24.sp - travel, 0),
            child: finger(-0.35),
          ),
          Transform.translate(
            offset: Offset(24.sp + travel, 0),
            child: finger(0.35),
          ),
        ],
      ),
    );
  }
}

/// Progress border identical to the one drawn on the other teaching cards:
/// two strokes growing symmetrically from the top-center down to the bottom.
class _PinchBorderProgressPainter extends CustomPainter {
  _PinchBorderProgressPainter({
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

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final r = borderRadius;
    final topCenter = w / 2;
    final bottomCenter = w / 2;

    final rightPath = Path()
      ..moveTo(topCenter, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(bottomCenter, h);

    final leftPath = Path()
      ..moveTo(topCenter, 0)
      ..lineTo(r, 0)
      ..arcToPoint(Offset(0, r), radius: Radius.circular(r), clockwise: false)
      ..lineTo(0, h - r)
      ..arcToPoint(Offset(r, h), radius: Radius.circular(r), clockwise: false)
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
  bool shouldRepaint(covariant _PinchBorderProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.borderRadius != borderRadius;
  }
}
