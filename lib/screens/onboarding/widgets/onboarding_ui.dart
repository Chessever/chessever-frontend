import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:motor/motor.dart';

/// Shared motion and controls for the onboarding flow.
///
/// These lived as private members of `onboarding_flow_screen.dart` while every
/// step was declared in that one file. Steps that warrant their own file need
/// the same easing and the same call-to-action, and a second copy would drift —
/// so they are one source here instead.

/// The default step easing: entrances, titles, cards settling into place.
final Curve onboardingSmoothSpring = Motion.smoothSpring().toCurve;

/// Tighter spring for direct manipulation, e.g. a button's press scale.
final Curve onboardingSnappySpring = Motion.snappySpring().toCurve;

/// Plain ease-out for the few places a spring's overshoot is unwanted, such as
/// a large image fading up.
const Curve onboardingGentleSpring = Curves.easeOutCubic;

/// The onboarding call-to-action.
///
/// Full-bleed, `textPrimary`-filled, and the only filled button on a step — the
/// flow deliberately pairs it with a quiet text link rather than an outlined
/// twin. Press feedback is a small scale plus a medium haptic; passing a null
/// [onTap] renders the disabled face instead of leaving a live-looking control
/// that does nothing.
class OnboardingPrimaryButton extends HookWidget {
  const OnboardingPrimaryButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.buttonKey,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);

    return GestureDetector(
      key: buttonKey,
      onTapDown: (_) => isPressed.value = true,
      onTapUp: (_) {
        isPressed.value = false;
        if (onTap != null) {
          HapticFeedback.mediumImpact();
          onTap!();
        }
      },
      onTapCancel: () => isPressed.value = false,
      child: AnimatedScale(
        scale: isPressed.value ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: onboardingSnappySpring,
        child: Container(
          width: double.infinity,
          height: 52.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.br),
            color:
                onTap != null
                    ? context.colors.textPrimary
                    : context.colors.textPrimary.withValues(alpha: 0.2),
          ),
          child: Center(
            child:
                isLoading
                    ? SizedBox(
                      width: 24.w,
                      height: 24.h,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.textInverse,
                      ),
                    )
                    : Text(
                      label,
                      style: AppTypography.textMdMedium.copyWith(
                        color:
                            onTap != null
                                ? context.colors.textInverse
                                : context.colors.textPrimary.withValues(
                                  alpha: 0.5,
                                ),
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}
