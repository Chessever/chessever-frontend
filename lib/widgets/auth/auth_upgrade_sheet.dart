import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:chessever2/previews/preview_support.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Show the auth upgrade sheet.
/// Returns `true` if the user ends up authenticated (non-anonymous) after closing.
Future<bool> showAuthUpgradeSheet({
  required BuildContext context,
  String? title,
  String? message,
  String? dismissLabel,
  bool completeSignInInSheet = false,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveHelper.bottomSheetConstraints,
    builder:
        (_) => _AuthUpgradeSheet(
          hostContext: context,
          title: title,
          message: message,
          dismissLabel: dismissLabel,
          completeSignInInSheet: completeSignInInSheet,
        ),
  );

  final user = Supabase.instance.client.auth.currentUser;
  return user != null && user.isAnonymous != true;
}

/// Kept as the single decision point for "does this action need an account?".
///
/// A guest (anonymous session) is a normal free account: same favorites, same
/// boards and same settings. Free features are not blocked here; account
/// creation is asked for on a schedule instead — see
/// `GuestSessionGateListener` (day 7 soft prompt, day 28 required).
/// Premium checkout is the one exception and owns its account requirement in
/// `showPremiumPaywallSheet`, where the purchase can resume after sign-in.
Future<bool> requireFullAuthGuard(BuildContext context) async {
  return true;
}

class _AuthUpgradeSheet extends HookWidget {
  const _AuthUpgradeSheet({
    required this.hostContext,
    this.title,
    this.message,
    this.dismissLabel,
    this.completeSignInInSheet = false,
  });

  final BuildContext hostContext;
  final String? title;
  final String? message;
  final String? dismissLabel;
  final bool completeSignInInSheet;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      // Sized so the list and both actions fit without scrolling — a list
      // sliced through the middle of a row reads as broken, and an escape
      // hatch below the fold is not an escape hatch.
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface.withValues(alpha: 0.98),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.sp)),
          ),
          child: _AuthUpgradePage(
            hostContext: hostContext,
            scrollController: scrollController,
            title: title,
            message: message,
            dismissLabel: dismissLabel,
            completeSignInInSheet: completeSignInInSheet,
          ),
        );
      },
    );
  }
}

class _AuthUpgradePage extends HookConsumerWidget {
  const _AuthUpgradePage({
    required this.hostContext,
    this.scrollController,
    this.title,
    this.message,
    this.dismissLabel,
    this.completeSignInInSheet = false,
  });

  final BuildContext hostContext;
  final ScrollController? scrollController;
  final String? title;
  final String? message;
  final String? dismissLabel;
  final bool completeSignInInSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSigningIn = useState(false);

    Future<void> startAuthFlow() async {
      Navigator.of(hostContext).pop(); // Close sheet first
      // Use host context so navigation happens on app navigator
      Navigator.of(hostContext).pushNamed('/auth_screen');
    }

    Future<void> signIn(Future<void> Function() signInMethod) async {
      final messenger = ScaffoldMessenger.of(context);
      isSigningIn.value = true;
      try {
        await signInMethod();
        if (context.mounted) Navigator.of(context).pop();
      } catch (error) {
        showAppSnackOn(
          messenger,
          userFacingError(
            error,
            fallback: 'Could not sign in. Please try again.',
          ),
          tone: AppSnackTone.danger,
        );
        if (context.mounted) isSigningIn.value = false;
      }
    }

    return Stack(
      children: [
        // Slow drifting motes give the dark sheet a pulse; on paper they are
        // haze, so light keeps the sheet clean. (The blurred cyan glow blobs
        // that once sat behind them were background glow, in either theme.)
        if (!context.isLightTheme)
          const Positioned.fill(child: _FloatingParticles()),
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
          // Actions are pinned below the scroll area: with longer copy (or a
          // large text scale) the content outgrows the sheet, and an escape
          // hatch you can only reach by scrolling is not an escape hatch.
          child: Column(
            children: [
              // Handle bar + close button row
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 36.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: context.colors.textPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2.br),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.7,
                        ),
                        size: 22.ic,
                      ),
                      onPressed: () => Navigator.of(hostContext).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      SizedBox(height: 8.h),
                      _UnlockVisual()
                          .animate()
                          .fadeIn(
                            duration: 600.ms,
                            curve: Motion.smoothSpring().toCurve,
                          )
                          .scale(
                            begin: const Offset(0.85, 0.85),
                            end: const Offset(1, 1),
                          ),
                      SizedBox(height: 16.h),
                      Text(
                        title ?? 'Unlock the full\nexperience',
                        textAlign: TextAlign.center,
                        style: AppTypography.displayXsBold.copyWith(
                          color: context.colors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        message ?? 'Create an account to access all features',
                        textAlign: TextAlign.center,
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.textInk(0.6),
                        ),
                      ),
                      SizedBox(height: 16.h),
                      _FeaturesList(),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              if (completeSignInInSheet)
                AbsorbPointer(
                  absorbing: isSigningIn.value,
                  child: AnimatedOpacity(
                    opacity: isSigningIn.value ? 0.55 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: Column(
                      children: [
                        if (Platform.isIOS) ...[
                          AuthButton(
                            signInTitle: 'Continue with Apple',
                            svgIconPath: SvgAsset.appleIcon,
                            onPressed:
                                () => signIn(
                                  () =>
                                      ref
                                          .read(authStateProvider.notifier)
                                          .signInWithApple(),
                                ),
                          ),
                          SizedBox(height: 12.h),
                        ],
                        AuthButton(
                          signInTitle: 'Continue with Google',
                          svgIconPath: SvgAsset.googleIcon,
                          onPressed:
                              () => signIn(
                                () =>
                                    ref
                                        .read(authStateProvider.notifier)
                                        .signInWithGoogle(),
                              ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                _PrimaryButton(
                  label: 'Create free account',
                  onTap: startAuthFlow,
                ),
              if (dismissLabel != null) ...[
                SizedBox(height: 4.h),
                _DismissButton(
                  label: dismissLabel!,
                  onTap: () => Navigator.of(hostContext).pop(),
                ),
              ],
              SizedBox(height: 8.h),
            ],
          ),
        ),
      ],
    );
  }
}

class _UnlockVisual extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final light = context.isLightTheme;
    // The disc stands on its own ring in both themes: a pulsing radial halo
    // and a cyan bloom behind it read as a sticker glow, not light.
    return SizedBox(
      height: 140.h,
      width: 140.w,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100.w,
            height: 100.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.surface.withValues(alpha: 0.9),
              border: Border.all(
                color:
                    light
                        ? context.colors.divider
                        : kPrimaryColor.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.cloud_done_outlined,
                size: 40.ic,
                color: context.colors.accentText,
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
    // Guests already have every feature — favorites, analyses, board themes.
    // What an account actually adds is durability, so sell that and nothing
    // else. Promising features they already use reads as a lie.
    final features = [
      _FeatureItem(
        icon: Icons.backup_outlined,
        title: 'Backed up',
        subtitle: 'Your players and analyses survive a lost phone',
        color: const Color(0xFF95E1D3),
      ),
      _FeatureItem(
        icon: Icons.devices_rounded,
        title: 'On every device',
        subtitle: 'Same favorites on your phone and tablet',
        color: const Color(0xFF7DD3FC),
      ),
      _FeatureItem(
        icon: Icons.workspace_premium_outlined,
        title: 'Purchases follow you',
        subtitle: 'Restore Premium after a reinstall',
        color: const Color(0xFF4ECDC4),
      ),
    ];

    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.br),
        color: context.colors.surface.withValues(alpha: 0.5),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          Text(
            'What an account adds:',
            style: AppTypography.textXsMedium.copyWith(
              color: context.textInk(0.5),
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 16.h),
          ...features.asMap().entries.map((entry) {
            final index = entry.key;
            final feature = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < features.length - 1 ? 12.h : 0,
              ),
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
    // Bare marks in both themes, no tinted tile behind them. The pastels
    // read on the dark sheet but sit near 1.4:1 on paper, so light draws the
    // mark in accent-text ink. The 40dp slot keeps the text column aligned.
    final light = context.isLightTheme;
    return Row(
      children: [
        SizedBox(
          width: 40.w,
          height: 40.h,
          child: Center(
            child: Icon(
              icon,
              size: 22.ic,
              color: light ? context.colors.accentText : color,
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
                  color: context.colors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: AppTypography.textXsRegular.copyWith(
                  color: context.textInk(0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends HookWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  static const _pressMotion = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 240),
    snapToEnd: true,
  );

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // One solid ink plate in both themes: the inverse of the page ink, so the
    // label clears AA by a wide margin (21:1 dark, ~15:1 paper) with no
    // gradient and no bloom under it.
    final colors = context.colors;

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => isPressed.value = true,
        onTapUp: (_) => isPressed.value = false,
        onTapCancel: () => isPressed.value = false,
        onTap: onTap,
        child: SingleMotionBuilder(
          motion: reduceMotion ? const Motion.none() : _pressMotion,
          value: isPressed.value ? 0.97 : 1.0,
          builder: (context, scale, child) => Transform.scale(
            // Springs settle a hair short of 1.0; snap so the label rasterises
            // crisp at rest.
            scale: (scale - 1).abs() < 0.002 ? 1.0 : scale,
            child: child,
          ),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: 52.h),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.br),
              color: colors.textPrimary,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.textMdMedium.copyWith(
                color: colors.textInverse,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet decline. Deliberately plain text (no fill, no outline) so it reads as
/// the lower-weight option next to the primary action without becoming the
/// stock filled/outlined button pair.
class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: Size(double.infinity, 48.h),
        foregroundColor: context.colors.textPrimary,
        overlayColor: context.colors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.br),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.textMdMedium.copyWith(
          color: context.textInk(0.6),
        ),
      ),
    );
  }
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
      final x =
          particle.x +
          math.sin(animation * 2 * math.pi + particle.x * 10) * 0.02;

      final paint =
          Paint()
            ..color = Colors.white.withValues(
              alpha: particle.opacity * (1 - y.abs() * 0.5),
            );

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

// ════════════════════════════════════════════════════════════════════════════
// PREVIEWS — `flutter widget-preview start`
// ════════════════════════════════════════════════════════════════════════════

/// The day-7 guest prompt, with the exact copy the gate passes.
///
/// Keep this in sync with `GuestSessionGateListener._showSoftPrompt`.
@Preview(
  name: 'Guest day 7 prompt',
  group: 'Guest upgrade',
  size: kPhonePreviewSize,
  brightness: Brightness.dark,
  theme: appPreviewTheme,
  wrapper: responsivePreviewHost,
)
Widget guestDay7PromptPreview() {
  const days = 7;
  return const _SheetPreviewHost(
    title: 'Keep your chess,\nwherever you play',
    message:
        '$days days as a guest. '
        'A free account keeps it all safe, on every device.',
    dismissLabel: 'Not now',
  );
}

/// The same sheet as reached from anywhere else (no scheduled-prompt copy, no
/// "Not now" — the close button is the only way out).
@Preview(
  name: 'Upgrade sheet (default copy)',
  group: 'Guest upgrade',
  size: kPhonePreviewSize,
  brightness: Brightness.dark,
  theme: appPreviewTheme,
  wrapper: responsivePreviewHost,
)
Widget authUpgradeSheetDefaultPreview() => const _SheetPreviewHost();

/// Renders the sheet body over a dark page, the way it looks on top of the app.
/// The sheet is normally inside a modal route; this supplies the surrounding
/// scaffold so it can be previewed on its own.
class _SheetPreviewHost extends StatelessWidget {
  const _SheetPreviewHost({this.title, this.message, this.dismissLabel});

  final String? title;
  final String? message;
  final String? dismissLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: Builder(
        // The sheet takes a host context for its pops; in the previewer that is
        // simply this subtree.
        builder:
            (hostContext) => _AuthUpgradeSheet(
              hostContext: hostContext,
              title: title,
              message: message,
              dismissLabel: dismissLabel,
            ),
      ),
    );
  }
}
