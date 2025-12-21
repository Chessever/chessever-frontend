import 'dart:async';
import 'dart:math' as math;
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/screens/onboarding/player_selection_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/notification_service.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Premium spring curves for buttery smooth animations
final Curve _smoothSpring = Motion.smoothSpring().toCurve;
final Curve _snappySpring = Motion.snappySpring().toCurve;
final Curve _gentleSpring = Curves.easeOutCubic; // Gentle fallback

class OnboardingFlowScreen extends HookConsumerWidget {
  const OnboardingFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageController = usePageController();
    final currentPage = useState(0);
    final countryState = ref.watch(countryDropdownProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Check if user is authenticated (not anonymous)
    final user = Supabase.instance.client.auth.currentUser;
    final isAuthenticated = user != null && user.isAnonymous != true;

    // Always 4 pages - final page content differs based on auth status
    const totalPages = 4;

    useEffect(() {
      ref.read(countryDropdownProvider);
      return null;
    }, const []);

    Future<void> goToPage(int index) async {
      await pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 500),
        curve: _smoothSpring,
      );
    }

    return ScreenWrapper(
      child: Scaffold(
        backgroundColor: kBackgroundColor,
        body: Stack(
          children: [
            // Ambient background glow
            const Positioned.fill(child: _AmbientGlow()),

            // Floating particles for premium feel
            const Positioned.fill(child: _FloatingParticles()),

            // Progress indicator at top
            Positioned(
              top: topPadding + 16.h,
              left: 24.w,
              right: 24.w,
              child: _PageIndicator(
                currentPage: currentPage.value,
                totalPages: totalPages,
              ),
            ),

            // Main content
            Positioned.fill(
              child: PageView(
                controller: pageController,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (index) => currentPage.value = index,
                children: [
                  _WelcomeStep(
                    onNext: () => goToPage(1),
                    topPadding: topPadding,
                    bottomPadding: bottomPadding,
                  ),
                  _CountryStep(
                    countryState: countryState,
                    onNext: () => goToPage(2),
                    onRetry: () => ref.invalidate(countryDropdownProvider),
                    topPadding: topPadding,
                    bottomPadding: bottomPadding,
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: topPadding + 60.h),
                    child: PlayerSelectionContent(
                      title: 'Pick your favorites',
                      subtitle: 'Follow 3+ players to personalize your feed',
                      actionLabel: 'Continue',
                      badgeLabel: null,
                      onComplete: () => goToPage(3),
                    ),
                  ),
                  // 4th page: Different content based on auth status
                  if (isAuthenticated)
                    _AuthenticatedUserStep(
                      user: user,
                      topPadding: topPadding,
                      bottomPadding: bottomPadding,
                      onContinue: () => markOnboardingComplete(context, ref),
                    )
                  else
                    _AuthStep(
                      topPadding: topPadding,
                      bottomPadding: bottomPadding,
                      onSignIn: () async {
                        // Request notification permission on last page of onboarding
                        unawaited(NotificationService.requestPermissionWithDialog());

                        // Mark onboarding as seen BEFORE navigating to auth
                        // This ensures user won't see onboarding again after signing in
                        // The pending favorites will be flushed by auth_state_listener
                        // when authentication completes
                        try {
                          await ref
                              .read(onboardingRepositoryProvider)
                              .markAsSeen(
                                userId:
                                    Supabase.instance.client.auth.currentUser?.id,
                              );
                          if (kDebugMode) {
                            debugPrint('[Onboarding] Marked as seen before auth navigation');
                          }
                        } catch (e) {
                          if (kDebugMode) {
                            debugPrint('[Onboarding] Failed to mark as seen: $e');
                          }
                        }
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/auth_screen');
                        }
                      },
                      onContinueAsGuest: () => markOnboardingComplete(context, ref),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// AUTH STEP - FOMO-inducing sign up encouragement
// ════════════════════════════════════════════════════════════════════════════

class _AuthStep extends HookWidget {
  const _AuthStep({
    required this.topPadding,
    required this.bottomPadding,
    required this.onSignIn,
    required this.onContinueAsGuest,
  });

  final double topPadding;
  final double bottomPadding;
  final VoidCallback onSignIn;
  final VoidCallback onContinueAsGuest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, topPadding + 60.h, 24.w, 16.h),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top content
                  Column(
                    children: [
                      SizedBox(height: 24.h),

                      // Lock icon with glow
                      _UnlockVisual()
                          .animate()
                          .fadeIn(duration: 600.ms, curve: _gentleSpring)
                          .scale(
                            begin: const Offset(0.8, 0.8),
                            end: const Offset(1, 1),
                            duration: 700.ms,
                            curve: _smoothSpring,
                          ),

                      SizedBox(height: 24.h),

                      // Title
                      Text(
                        'Unlock the full\nexperience',
                        textAlign: TextAlign.center,
                        style: AppTypography.displayXsBold.copyWith(
                          color: kWhiteColor,
                          height: 1.2,
                        ),
                      )
                          .animate(delay: 200.ms)
                          .fadeIn(duration: 500.ms, curve: _smoothSpring)
                          .move(begin: const Offset(0, 16), curve: _smoothSpring),

                      SizedBox(height: 8.h),

                      Text(
                        'Create an account to access all features',
                        textAlign: TextAlign.center,
                        style: AppTypography.textSmRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.6),
                        ),
                      )
                          .animate(delay: 300.ms)
                          .fadeIn(duration: 500.ms, curve: _smoothSpring),

                      SizedBox(height: 24.h),

                      // FOMO feature list
                      _FeaturesList()
                          .animate(delay: 400.ms)
                          .fadeIn(duration: 500.ms, curve: _smoothSpring)
                          .move(begin: const Offset(0, 20), curve: _smoothSpring),
                    ],
                  ),

                  // Bottom buttons
                  Column(
                    children: [
                      SizedBox(height: 24.h),

                      // Sign in button (primary)
                      _PrimaryButton(
                        label: 'Create free account',
                        onTap: onSignIn,
                      )
                          .animate(delay: 600.ms)
                          .fadeIn(duration: 400.ms, curve: _smoothSpring)
                          .move(begin: const Offset(0, 30), curve: _smoothSpring),

                      SizedBox(height: 12.h),

                      // Continue as guest (secondary)
                      _SecondaryButton(
                        label: 'Continue without account',
                        onTap: onContinueAsGuest,
                      )
                          .animate(delay: 700.ms)
                          .fadeIn(duration: 400.ms, curve: _smoothSpring),

                      SizedBox(height: 12.h),

                      // Warning note
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
                      )
                          .animate(delay: 800.ms)
                          .fadeIn(duration: 400.ms, curve: _smoothSpring),

                      SizedBox(height: 20.h),

                      // "I have an account" link
                      GestureDetector(
                        onTap: onSignIn,
                        child: Text(
                          'I already have an account',
                          style: AppTypography.textSmMedium.copyWith(
                            color: kPrimaryColor,
                          ),
                        ),
                      )
                          .animate(delay: 900.ms)
                          .fadeIn(duration: 400.ms, curve: _smoothSpring),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
          // Outer glow
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

          // Inner circle with lock
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
        // Icon container
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
        // Text
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
        // Lock indicator
        Icon(
          Icons.lock_outline_rounded,
          size: 16.ic,
          color: kWhiteColor.withValues(alpha: 0.25),
        ),
      ],
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
        HapticFeedback.lightImpact();
        onTap();
      },
      onTapCancel: () => isPressed.value = false,
      child: AnimatedScale(
        scale: isPressed.value ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: _snappySpring,
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

// ════════════════════════════════════════════════════════════════════════════
// AUTHENTICATED USER STEP - Welcome back for existing users
// ════════════════════════════════════════════════════════════════════════════

class _AuthenticatedUserStep extends HookWidget {
  const _AuthenticatedUserStep({
    required this.user,
    required this.topPadding,
    required this.bottomPadding,
    required this.onContinue,
  });

  final User user;
  final double topPadding;
  final double bottomPadding;
  final VoidCallback onContinue;

  String get _displayName {
    // Try to get display name from user metadata
    final metadata = user.userMetadata;
    if (metadata != null) {
      final name = metadata['full_name'] ?? metadata['name'];
      if (name != null && name.toString().isNotEmpty) {
        return name.toString();
      }
    }
    // Fallback to email prefix
    final email = user.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }
    return 'Chess Player';
  }

  String? get _avatarUrl {
    final metadata = user.userMetadata;
    if (metadata != null) {
      return metadata['avatar_url']?.toString();
    }
    return null;
  }

  String get _initials {
    final name = _displayName;
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, topPadding + 60.h, 24.w, 16.h),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top content
                  Column(
                    children: [
                      SizedBox(height: 32.h),

                      // User avatar with glow
                      _UserAvatarVisual(
                        avatarUrl: _avatarUrl,
                        initials: _initials,
                      )
                          .animate()
                          .fadeIn(duration: 600.ms, curve: _gentleSpring)
                          .scale(
                            begin: const Offset(0.8, 0.8),
                            end: const Offset(1, 1),
                            duration: 700.ms,
                            curve: _smoothSpring,
                          ),

                      SizedBox(height: 32.h),

                      // Welcome message
                      Text(
                        'Welcome back,',
                        textAlign: TextAlign.center,
                        style: AppTypography.textMdRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.6),
                        ),
                      )
                          .animate(delay: 200.ms)
                          .fadeIn(duration: 500.ms, curve: _smoothSpring),

                      SizedBox(height: 4.h),

                      Text(
                        _displayName,
                        textAlign: TextAlign.center,
                        style: AppTypography.displayXsBold.copyWith(
                          color: kWhiteColor,
                          height: 1.2,
                        ),
                      )
                          .animate(delay: 300.ms)
                          .fadeIn(duration: 500.ms, curve: _smoothSpring)
                          .move(begin: const Offset(0, 16), curve: _smoothSpring),

                      SizedBox(height: 24.h),

                      // Confirmation text
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 20.sp, vertical: 16.sp),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16.br),
                          color: kGreenColor.withValues(alpha: 0.08),
                          border: Border.all(
                            color: kGreenColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 32.w,
                              height: 32.h,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: kGreenColor.withValues(alpha: 0.15),
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 18.ic,
                                color: kGreenColor,
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your preferences are saved',
                                    style: AppTypography.textSmMedium.copyWith(
                                      color: kWhiteColor,
                                    ),
                                  ),
                                  Text(
                                    'Synced across all your devices',
                                    style: AppTypography.textXsRegular.copyWith(
                                      color: kWhiteColor.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                          .animate(delay: 450.ms)
                          .fadeIn(duration: 500.ms, curve: _smoothSpring)
                          .move(begin: const Offset(0, 20), curve: _smoothSpring),
                    ],
                  ),

                  // Bottom button
                  Column(
                    children: [
                      SizedBox(height: 24.h),

                      // Continue button
                      _PrimaryButton(
                        label: 'Continue to Chessever',
                        onTap: onContinue,
                      )
                          .animate(delay: 600.ms)
                          .fadeIn(duration: 400.ms, curve: _smoothSpring)
                          .move(begin: const Offset(0, 30), curve: _smoothSpring),

                      SizedBox(height: 16.h),

                      // Subtle app branding
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            PngAsset.newAppLogoCircle,
                            height: 20.h,
                            width: 20.w,
                          ),
                          SizedBox(width: 8.w),
                          Text(
                            'Your chess journey continues',
                            style: AppTypography.textXsRegular.copyWith(
                              color: kWhiteColor.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      )
                          .animate(delay: 750.ms)
                          .fadeIn(duration: 400.ms, curve: _smoothSpring),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UserAvatarVisual extends HookWidget {
  const _UserAvatarVisual({
    required this.avatarUrl,
    required this.initials,
  });

  final String? avatarUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final pulseController = useAnimationController(
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    final pulseAnimation = useAnimation(
      CurvedAnimation(parent: pulseController, curve: Curves.easeInOut),
    );

    return SizedBox(
      height: 160.h,
      width: 160.w,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          Transform.scale(
            scale: 1.0 + pulseAnimation * 0.06,
            child: Container(
              width: 150.w,
              height: 150.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kGreenColor.withValues(alpha: 0.18),
                    kGreenColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // Middle ring
          Container(
            width: 130.w,
            height: 130.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: kGreenColor.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
          ),

          // Avatar container
          Container(
            width: 110.w,
            height: 110.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kBlack2Color.withValues(alpha: 0.9),
              border: Border.all(
                color: kGreenColor.withValues(alpha: 0.4),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: kGreenColor.withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipOval(
              child: avatarUrl != null
                  ? Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildInitials(),
                    )
                  : _buildInitials(),
            ),
          ),

          // Verified badge
          Positioned(
            bottom: 20.h,
            right: 20.w,
            child: Container(
              width: 32.w,
              height: 32.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kGreenColor,
                border: Border.all(
                  color: kBackgroundColor,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: kGreenColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Icon(
                Icons.check_rounded,
                size: 18.ic,
                color: kWhiteColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitials() {
    return Center(
      child: Text(
        initials,
        style: AppTypography.displaySmBold.copyWith(
          color: kWhiteColor,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// AMBIENT BACKGROUND GLOW
// ════════════════════════════════════════════════════════════════════════════

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
    // Primary glow - subtle movement
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

    // Secondary glow
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

// ════════════════════════════════════════════════════════════════════════════
// FLOATING PARTICLES
// ════════════════════════════════════════════════════════════════════════════

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

// ════════════════════════════════════════════════════════════════════════════
// PAGE INDICATOR
// ════════════════════════════════════════════════════════════════════════════

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.currentPage,
    required this.totalPages,
  });

  final int currentPage;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalPages, (index) {
        final isActive = index <= currentPage;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: _smoothSpring,
            margin: EdgeInsets.symmetric(horizontal: 3.w),
            height: 4.h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2.br),
              color: isActive
                  ? kPrimaryColor
                  : kWhiteColor.withValues(alpha: 0.12),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: kPrimaryColor.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// WELCOME STEP - Hero visual with minimal text
// ════════════════════════════════════════════════════════════════════════════

class _WelcomeStep extends HookWidget {
  const _WelcomeStep({
    required this.onNext,
    required this.topPadding,
    required this.bottomPadding,
  });

  final VoidCallback onNext;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, topPadding + 60.h, 24.w, bottomPadding + 16.h),
      child: Column(
        children: [
          const Spacer(flex: 1),

          // Hero visual - Animated chess knight
          _AnimatedKnightHero()
              .animate()
              .fadeIn(duration: 600.ms, curve: _gentleSpring)
              .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1, 1),
                duration: 800.ms,
                curve: _smoothSpring,
              ),

          SizedBox(height: 48.h),

          // App logo
          Image.asset(
            PngAsset.newAppLogoCircle,
            height: 56.h,
            width: 56.w,
          )
              .animate(delay: 200.ms)
              .fadeIn(duration: 500.ms, curve: _smoothSpring)
              .scale(begin: const Offset(0.5, 0.5), curve: _snappySpring),

          SizedBox(height: 24.h),

          // Tagline - minimal text
          Text(
            'Your chess.\nYour way.',
            textAlign: TextAlign.center,
            style: AppTypography.displayXsBold.copyWith(
              color: kWhiteColor,
              height: 1.2,
            ),
          )
              .animate(delay: 300.ms)
              .fadeIn(duration: 500.ms, curve: _smoothSpring)
              .move(begin: const Offset(0, 20), curve: _smoothSpring),

          SizedBox(height: 12.h),

          Text(
            'Follow players • Track events • Analyze games',
            textAlign: TextAlign.center,
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.6),
              letterSpacing: 0.3,
            ),
          )
              .animate(delay: 450.ms)
              .fadeIn(duration: 500.ms, curve: _smoothSpring),

          const Spacer(flex: 2),

          // CTA Button
          _PrimaryButton(
            label: 'Get started',
            onTap: onNext,
          )
              .animate(delay: 600.ms)
              .fadeIn(duration: 400.ms, curve: _smoothSpring)
              .move(begin: const Offset(0, 30), curve: _smoothSpring),

          SizedBox(height: 8.h),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ANIMATED KNIGHT HERO
// ════════════════════════════════════════════════════════════════════════════

class _AnimatedKnightHero extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final breatheController = useAnimationController(
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    final breatheAnimation = useAnimation(
      CurvedAnimation(parent: breatheController, curve: Curves.easeInOut),
    );

    return SizedBox(
      height: 200.h,
      width: 200.w,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          Transform.scale(
            scale: 1.0 + breatheAnimation * 0.05,
            child: Container(
              width: 180.w,
              height: 180.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kPrimaryColor.withValues(alpha: 0.15),
                    kPrimaryColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // Chess pattern background
          _ChessPatternCircle(animation: breatheAnimation),

          // Knight piece icon
          Transform.translate(
            offset: Offset(0, -3 + breatheAnimation * 6),
            child: _KnightIcon(size: 100.sp),
          ),
        ],
      ),
    );
  }
}

class _ChessPatternCircle extends StatelessWidget {
  const _ChessPatternCircle({required this.animation});

  final double animation;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: animation * 0.1,
      child: Container(
        width: 140.w,
        height: 140.h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: kWhiteColor.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: ClipOval(
          child: CustomPaint(
            painter: _MiniChessBoardPainter(),
            size: Size(140.w, 140.h),
          ),
        ),
      ),
    );
  }
}

class _MiniChessBoardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final squareSize = size.width / 4;
    final lightColor = kWhiteColor.withValues(alpha: 0.06);
    final darkColor = kBlack2Color.withValues(alpha: 0.4);

    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        final isLight = (row + col) % 2 == 0;
        final paint = Paint()..color = isLight ? lightColor : darkColor;

        canvas.drawRect(
          Rect.fromLTWH(
            col * squareSize,
            row * squareSize,
            squareSize,
            squareSize,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _KnightIcon extends StatelessWidget {
  const _KnightIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.sp),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kBlack2Color.withValues(alpha: 0.8),
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
      child: Text(
        '♞',
        style: TextStyle(
          fontSize: size * 0.5,
          color: kWhiteColor,
          height: 1,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// COUNTRY STEP - Visual flag selection
// ════════════════════════════════════════════════════════════════════════════

class _CountryStep extends HookConsumerWidget {
  const _CountryStep({
    required this.countryState,
    required this.onNext,
    required this.onRetry,
    required this.topPadding,
    required this.bottomPadding,
  });

  final AsyncValue<Country> countryState;
  final VoidCallback onNext;
  final VoidCallback onRetry;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, topPadding + 60.h, 24.w, bottomPadding + 16.h),
      child: Column(
        children: [
          const Spacer(flex: 1),

          // Globe visual with flag
          _GlobeVisual(countryState: countryState)
              .animate()
              .fadeIn(duration: 600.ms, curve: _gentleSpring)
              .scale(
                begin: const Offset(0.85, 0.85),
                end: const Offset(1, 1),
                duration: 700.ms,
                curve: _smoothSpring,
              ),

          SizedBox(height: 40.h),

          // Title
          Text(
            'Where are you from?',
            textAlign: TextAlign.center,
            style: AppTypography.displayXsBold.copyWith(
              color: kWhiteColor,
            ),
          )
              .animate(delay: 200.ms)
              .fadeIn(duration: 500.ms, curve: _smoothSpring)
              .move(begin: const Offset(0, 16), curve: _smoothSpring),

          SizedBox(height: 8.h),

          Text(
            'We\'ll show you players from your region',
            textAlign: TextAlign.center,
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.6),
            ),
          )
              .animate(delay: 300.ms)
              .fadeIn(duration: 500.ms, curve: _smoothSpring),

          SizedBox(height: 32.h),

          // Country selector card
          _CountryCard(
            countryState: countryState,
            onRetry: onRetry,
            ref: ref,
          )
              .animate(delay: 400.ms)
              .fadeIn(duration: 500.ms, curve: _smoothSpring)
              .move(begin: const Offset(0, 20), curve: _smoothSpring),

          const Spacer(flex: 2),

          // CTA Button
          _PrimaryButton(
            label: 'Continue',
            onTap: countryState.isLoading ? null : onNext,
            isLoading: countryState.isLoading,
          )
              .animate(delay: 550.ms)
              .fadeIn(duration: 400.ms, curve: _smoothSpring)
              .move(begin: const Offset(0, 30), curve: _smoothSpring),

          SizedBox(height: 8.h),
        ],
      ),
    );
  }
}

class _GlobeVisual extends HookWidget {
  const _GlobeVisual({required this.countryState});

  final AsyncValue<Country> countryState;

  @override
  Widget build(BuildContext context) {
    final rotateController = useAnimationController(
      duration: const Duration(seconds: 20),
    )..repeat();

    final rotateAnimation = useAnimation(rotateController);

    return SizedBox(
      height: 180.h,
      width: 180.w,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating ring
          Transform.rotate(
            angle: rotateAnimation * 2 * math.pi,
            child: Container(
              width: 160.w,
              height: 160.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: kPrimaryColor.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 75.w,
                    child: _OrbitDot(color: kPrimaryColor.withValues(alpha: 0.6)),
                  ),
                  Positioned(
                    bottom: 20.h,
                    right: 10.w,
                    child: _OrbitDot(color: kPrimaryColor.withValues(alpha: 0.4)),
                  ),
                ],
              ),
            ),
          ),

          // Globe icon
          Container(
            width: 100.w,
            height: 100.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kBlack2Color.withValues(alpha: 0.9),
              border: Border.all(
                color: kWhiteColor.withValues(alpha: 0.1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: kPrimaryColor.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: countryState.when(
              loading: () => Center(
                child: SizedBox(
                  width: 24.w,
                  height: 24.h,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kPrimaryColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
              error: (_, __) => Icon(
                Icons.public,
                size: 48.ic,
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
              data: (country) => Center(
                child: Text(
                  country.flagEmoji,
                  style: TextStyle(fontSize: 48.f),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitDot extends StatelessWidget {
  const _OrbitDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6.w,
      height: 6.h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

class _CountryCard extends StatelessWidget {
  const _CountryCard({
    required this.countryState,
    required this.onRetry,
    required this.ref,
  });

  final AsyncValue<Country> countryState;
  final VoidCallback onRetry;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.br),
        color: kBlack2Color.withValues(alpha: 0.6),
        border: Border.all(
          color: kWhiteColor.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: countryState.when(
        loading: () => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18.w,
              height: 18.h,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
            ),
            SizedBox(width: 12.w),
            Text(
              'Finding your location...',
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        error: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Couldn\'t detect location',
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(width: 12.w),
            GestureDetector(
              onTap: onRetry,
              child: Text(
                'Retry',
                style: AppTypography.textSmMedium.copyWith(
                  color: kPrimaryColor,
                ),
              ),
            ),
          ],
        ),
        data: (country) => CountryDropdown(
          selectedCountryCode: country.countryCode,
          onChanged: (Country newCountry) {
            ref
                .read(countryDropdownProvider.notifier)
                .selectCountry(newCountry.countryCode);
          },
          requireAuthToChange: false,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PRIMARY BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _PrimaryButton extends HookWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);

    return GestureDetector(
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
        curve: _snappySpring,
        child: Container(
          width: double.infinity,
          height: 56.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.br),
            color: onTap != null ? kWhiteColor : kWhiteColor.withValues(alpha: 0.2),
            boxShadow: onTap != null
                ? [
                    BoxShadow(
                      color: kWhiteColor.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 24.w,
                    height: 24.h,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kBlackColor,
                    ),
                  )
                : Text(
                    label,
                    style: AppTypography.textMdMedium.copyWith(
                      color: onTap != null
                          ? kBlackColor
                          : kWhiteColor.withValues(alpha: 0.5),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
