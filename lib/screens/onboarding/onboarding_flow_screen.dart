import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/screens/onboarding/player_selection_screen.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/services/appsflyer_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/services/push_notifications_service.dart';
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

      // Log onboarding start for affiliate tracking
      AnalyticsService.instance.trackEventDetached('Onboarding Started');
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
        key: e2eKey(E2eIds.onboardingRoot),
        backgroundColor: context.colors.background,
        body: Stack(
          children: [
            // Progress indicator at top
            Positioned(
              top: topPadding + 16.h,
              left: 0,
              right: 0,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth:
                        ResponsiveHelper.isTablet ? 500.0 : double.infinity,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.adaptive(
                        phone: 24.w,
                        tablet: 32.w,
                      ),
                    ),
                    child: _PageIndicator(
                      currentPage: currentPage.value,
                      totalPages: totalPages,
                    ),
                  ),
                ),
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
                    onSignIn: () async {
                      // Ask for notifications on direct auth path too.
                      // Some users sign in from the first page and skip the last step.
                      if (!E2eConfig.suppressInterruptivePrompts) {
                        unawaited(
                          PushNotificationsService.instance
                              .requestPermissionWithDialog(),
                        );
                      }

                      // Mark onboarding as seen before navigating to auth
                      try {
                        await ref
                            .read(onboardingRepositoryProvider)
                            .markAsSeen(
                              userId:
                                  Supabase.instance.client.auth.currentUser?.id,
                            );
                        if (kDebugMode) {
                          debugPrint(
                            '[Onboarding] Marked as seen before auth navigation',
                          );
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
                    padding: EdgeInsets.only(
                      top: topPadding + 60.h,
                      left: ResponsiveHelper.isTablet ? 16.w : 0,
                      right: ResponsiveHelper.isTablet ? 16.w : 0,
                    ),
                    child: PlayerSelectionContent(
                      title: 'Follow 3 players to get started',
                      subtitle: 'Pick up to 3 now — add more after signing in.',
                      actionLabel: 'Continue',
                      badgeLabel: null,
                      onComplete: () async {
                        // iOS only: ask for ATT consent here so the install
                        // can be attributed to the creator/campaign that
                        // referred the user. Pre-prompt explains "why" first;
                        // the system dialog only fires if the user agrees.
                        // No-op on Android, on test runs, or if already decided.
                        await _maybeShowAttPrePrompt(context);
                        if (context.mounted) await goToPage(3);
                      },
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
                        if (!E2eConfig.suppressInterruptivePrompts) {
                          unawaited(
                            PushNotificationsService.instance
                                .requestPermissionWithDialog(),
                          );
                        }

                        try {
                          await ref
                              .read(onboardingRepositoryProvider)
                              .markAsSeen(
                                userId:
                                    Supabase
                                        .instance
                                        .client
                                        .auth
                                        .currentUser
                                        ?.id,
                              );
                          if (kDebugMode) {
                            debugPrint(
                              '[Onboarding] Marked as seen before auth navigation',
                            );
                          }
                        } catch (e) {
                          if (kDebugMode) {
                            debugPrint(
                              '[Onboarding] Failed to mark as seen: $e',
                            );
                          }
                        }
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(
                            context,
                            '/auth_screen',
                          );
                        }
                      },
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
  });

  final double topPadding;
  final double bottomPadding;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    // Tablet-specific constraints
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 24.w,
      tablet: 32.w,
    );
    final maxWidth = ResponsiveHelper.isTablet ? 500.0 : double.infinity;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding + 50.h,
            horizontalPadding,
            bottomPadding + 8.h,
          ),
          child: Column(
            children: [
              // Top content - scrollable if needed but designed to fit
              Expanded(
                child: Column(
                  children: [
                    SizedBox(height: 8.h),

                    // Lock icon with glow - smaller size
                    _UnlockVisual()
                        .animate()
                        .fadeIn(duration: 600.ms, curve: _gentleSpring)
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1, 1),
                          duration: 700.ms,
                          curve: _smoothSpring,
                        ),

                    SizedBox(height: 16.h),

                    // Title
                    Text(
                          'Unlock the full\nexperience',
                          textAlign: TextAlign.center,
                          style: AppTypography.displayXsBold.copyWith(
                            color: context.colors.textPrimary,
                            height: 1.2,
                          ),
                        )
                        .animate(delay: 200.ms)
                        .fadeIn(duration: 500.ms, curve: _smoothSpring)
                        .move(begin: const Offset(0, 16), curve: _smoothSpring),

                    SizedBox(height: 6.h),

                    Text(
                          'Create an account to access all features',
                          textAlign: TextAlign.center,
                          style: AppTypography.textSmRegular.copyWith(
                            color: context.colors.textPrimary.withValues(alpha: 0.6),
                          ),
                        )
                        .animate(delay: 300.ms)
                        .fadeIn(duration: 500.ms, curve: _smoothSpring),

                    SizedBox(height: 16.h),

                    // FOMO feature list
                    Expanded(
                      child: _FeaturesList()
                          .animate(delay: 400.ms)
                          .fadeIn(duration: 500.ms, curve: _smoothSpring)
                          .move(
                            begin: const Offset(0, 20),
                            curve: _smoothSpring,
                          ),
                    ),
                  ],
                ),
              ),

              // Bottom buttons - fixed at bottom
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 12.h),

                  // Sign in button (primary)
                  _PrimaryButton(label: 'Create free account', onTap: onSignIn)
                      .animate(delay: 600.ms)
                      .fadeIn(duration: 400.ms, curve: _smoothSpring)
                      .move(begin: const Offset(0, 30), curve: _smoothSpring),

                  SizedBox(height: 12.h),

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
      height: 100.h,
      width: 100.w,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          Transform.scale(
            scale: 1.0 + pulseAnimation * 0.08,
            child: Container(
              width: 95.w,
              height: 95.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kPrimaryColor.withOpacity(0.2),
                    kPrimaryColor.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          // Inner circle with lock
          Container(
            width: 72.w,
            height: 72.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.surface.withOpacity(0.9),
              border: Border.all(
                color: kPrimaryColor.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: kPrimaryColor.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.lock_open_rounded,
                size: 32.ic,
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
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.br),
        color: context.colors.surface.withOpacity(0.5),
        border: Border.all(color: context.colors.textPrimary.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'What you\'ll get with an account:',
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 10.h),
          ...features.asMap().entries.map((entry) {
            final index = entry.key;
            final feature = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < features.length - 1 ? 8.h : 0,
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
    return Row(
      children: [
        // Icon container
        Container(
          width: 34.w,
          height: 34.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.br),
            color: color.withOpacity(0.15),
          ),
          child: Center(child: Icon(icon, size: 18.ic, color: color)),
        ),
        SizedBox(width: 10.w),
        // Text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
              ),
              Text(
                subtitle,
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        // Lock indicator
        Icon(
          Icons.lock_outline_rounded,
          size: 14.ic,
          color: context.colors.textPrimary.withValues(alpha: 0.25),
        ),
      ],
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
    // Tablet-specific constraints
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 24.w,
      tablet: 32.w,
    );
    final maxWidth = ResponsiveHelper.isTablet ? 500.0 : double.infinity;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding + 60.h,
            horizontalPadding,
            16.h,
          ),
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
                                  color: context.colors.textPrimary.withValues(alpha: 0.6),
                                ),
                              )
                              .animate(delay: 200.ms)
                              .fadeIn(duration: 500.ms, curve: _smoothSpring),

                          SizedBox(height: 4.h),

                          Text(
                                _displayName,
                                textAlign: TextAlign.center,
                                style: AppTypography.displayXsBold.copyWith(
                                  color: context.colors.textPrimary,
                                  height: 1.2,
                                ),
                              )
                              .animate(delay: 300.ms)
                              .fadeIn(duration: 500.ms, curve: _smoothSpring)
                              .move(
                                begin: const Offset(0, 16),
                                curve: _smoothSpring,
                              ),

                          SizedBox(height: 24.h),

                          // Confirmation text
                          Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20.sp,
                                  vertical: 16.sp,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16.br),
                                  color: kGreenColor.withOpacity(0.08),
                                  border: Border.all(
                                    color: kGreenColor.withOpacity(0.2),
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
                                        color: kGreenColor.withOpacity(0.15),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Your preferences are saved',
                                            style: AppTypography.textSmMedium
                                                .copyWith(color: context.colors.textPrimary),
                                          ),
                                          Text(
                                            'Synced across all your devices',
                                            style: AppTypography.textXsRegular
                                                .copyWith(
                                                  color: context.colors.textPrimary
                                                      .withOpacity(0.5),
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
                              .move(
                                begin: const Offset(0, 20),
                                curve: _smoothSpring,
                              ),
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
                                buttonKey: e2eKey(
                                  E2eIds.onboardingAuthenticatedContinueButton,
                                ),
                              )
                              .animate(delay: 600.ms)
                              .fadeIn(duration: 400.ms, curve: _smoothSpring)
                              .move(
                                begin: const Offset(0, 30),
                                curve: _smoothSpring,
                              ),

                          SizedBox(height: 16.h),

                          // Subtle app branding
                          Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    PngAsset.newAppLogoCircle,
                                    height: 20.h,
                                    width: 20.w,
                                    cacheWidth:
                                        (20 *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ))
                                            .toInt(),
                                    cacheHeight:
                                        (20 *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ))
                                            .toInt(),
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    'Your chess journey continues',
                                    style: AppTypography.textXsRegular.copyWith(
                                      color: context.colors.textPrimary.withValues(alpha: 0.4),
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
        ),
      ),
    );
  }
}

class _UserAvatarVisual extends HookWidget {
  const _UserAvatarVisual({required this.avatarUrl, required this.initials});

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
                    kGreenColor.withOpacity(0.18),
                    kGreenColor.withOpacity(0.0),
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
                color: kGreenColor.withOpacity(0.15),
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
              color: context.colors.surface.withOpacity(0.9),
              border: Border.all(
                color: kGreenColor.withOpacity(0.4),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: kGreenColor.withOpacity(0.2),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipOval(
              child:
                  avatarUrl != null
                      ? Image.network(
                        avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildInitials(context),
                      )
                      : _buildInitials(context),
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
                border: Border.all(color: context.colors.background, width: 3),
                boxShadow: [
                  BoxShadow(color: kGreenColor.withOpacity(0.4), blurRadius: 8),
                ],
              ),
              child: Icon(Icons.check_rounded, size: 18.ic, color: context.colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitials(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: AppTypography.displaySmBold.copyWith(
          color: context.colors.textPrimary,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// AMBIENT BACKGROUND GLOW
// ════════════════════════════════════════════════════════════════════════════

// ignore: unused_element
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
    final paint1 =
        Paint()
          ..color = kPrimaryColor.withOpacity(0.08 + (animation * 0.04))
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
    final paint2 =
        Paint()
          ..color = const Color(
            0xFF08647F,
          ).withOpacity(0.06 + (animation * 0.03))
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

// ignore: unused_element
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

      final paint = Paint()
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
// PAGE INDICATOR
// ════════════════════════════════════════════════════════════════════════════

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.currentPage, required this.totalPages});

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
              color: isActive ? kPrimaryColor : context.colors.textPrimary.withValues(alpha: 0.12),
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
    required this.onSignIn,
    required this.topPadding,
    required this.bottomPadding,
  });

  final VoidCallback onNext;
  final VoidCallback onSignIn;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    // Tablet-specific constraints
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 24.w,
      tablet: 32.w,
    );
    final maxWidth = ResponsiveHelper.isTablet ? 500.0 : double.infinity;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding + 60.h,
            horizontalPadding,
            bottomPadding + 16.h,
          ),
          child: Column(
            children: [
              const Spacer(flex: 1),

              // App logo
              Image.asset(
                    PngAsset.newAppLogoCircle,
                    height: 120.h,
                    width: 120.w,
                    cacheWidth:
                        (120 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                    cacheHeight:
                        (120 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                  )
                  .animate()
                  .fadeIn(duration: 600.ms, curve: _gentleSpring)
                  .scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1, 1),
                    duration: 800.ms,
                    curve: _smoothSpring,
                  ),

              SizedBox(height: 48.h),

              // Tagline - "Follow Chess Better."
              RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: AppTypography.displayXsBold.copyWith(
                        color: context.colors.textPrimary,
                        height: 1.2,
                      ),
                      children: [
                        const TextSpan(text: 'Follow Chess '),
                        TextSpan(
                          text: 'Better.',
                          style: AppTypography.displayXsBold.copyWith(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  )
                  .animate(delay: 300.ms)
                  .fadeIn(duration: 500.ms, curve: _smoothSpring)
                  .move(begin: const Offset(0, 20), curve: _smoothSpring),

              SizedBox(height: 12.h),

              Text(
                    'Follow players, Track Events, Analyze games',
                    textAlign: TextAlign.center,
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.6),
                      letterSpacing: 0.3,
                    ),
                  )
                  .animate(delay: 450.ms)
                  .fadeIn(duration: 500.ms, curve: _smoothSpring),

              const Spacer(flex: 2),

              // CTA Button
              _PrimaryButton(label: 'Get Started', onTap: onNext)
                  .animate(delay: 600.ms)
                  .fadeIn(duration: 400.ms, curve: _smoothSpring)
                  .move(begin: const Offset(0, 30), curve: _smoothSpring),

              SizedBox(height: 16.h),

              // Sign in link for returning users
              GestureDetector(
                    onTap: onSignIn,
                    child: Text(
                      'I already have an account',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kPrimaryColor,
                      ),
                    ),
                  )
                  .animate(delay: 700.ms)
                  .fadeIn(duration: 400.ms, curve: _smoothSpring),

              SizedBox(height: 8.h),
            ],
          ),
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
    // Tablet-specific constraints
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 24.w,
      tablet: 32.w,
    );
    final maxWidth = ResponsiveHelper.isTablet ? 500.0 : double.infinity;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding + 60.h,
            horizontalPadding,
            bottomPadding + 16.h,
          ),
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
                      color: context.colors.textPrimary,
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
                      color: context.colors.textPrimary.withValues(alpha: 0.6),
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
        ),
      ),
    );
  }
}

class _GlobeVisual extends StatelessWidget {
  const _GlobeVisual({required this.countryState});

  final AsyncValue<Country> countryState;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100.w,
      height: 100.h,
      decoration: BoxDecoration(shape: BoxShape.circle, color: context.colors.surface),
      child: countryState.when(
        loading:
            () => Center(
              child: SizedBox(
                width: 24.w,
                height: 24.h,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.textPrimary.withValues(alpha: 0.6),
                ),
              ),
            ),
        error:
            (_, __) => Icon(
              Icons.public,
              size: 48.ic,
              color: context.colors.textPrimary.withValues(alpha: 0.5),
            ),
        data:
            (country) => Center(
              child: Text(country.flagEmoji, style: TextStyle(fontSize: 48.f)),
            ),
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
        borderRadius: BorderRadius.circular(12.br),
        color: context.colors.surface,
      ),
      child: countryState.when(
        loading:
            () => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18.w,
                  height: 18.h,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.textPrimary.withValues(alpha: 0.5),
                  ),
                ),
                SizedBox(width: 12.w),
                Text(
                  'Finding your location...',
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
        error:
            (_, __) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Couldn\'t detect location',
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.6),
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
        data:
            (country) => CountryDropdown(
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
    this.buttonKey,
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
        curve: _snappySpring,
        child: Container(
          width: double.infinity,
          height: 52.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.br),
            color: onTap != null ? context.colors.textPrimary : context.colors.textPrimary.withValues(alpha: 0.2),
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
                                : context.colors.textPrimary.withValues(alpha: 0.5),
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ATT PRE-PROMPT — explains why we ask, then triggers Apple's system dialog.
// ════════════════════════════════════════════════════════════════════════════

Future<void> _maybeShowAttPrePrompt(BuildContext context) async {
  // Every path through this function MUST end with startSdkIfNotYetStarted()
  // so the install event fires with the correct ATT/IDFA state. Without
  // this, users who skip the prompt (Android, E2E, already-decided, "Not
  // now") would only get startSDK from the 120s fallback timer.
  try {
    if (!Platform.isIOS) return;
    if (E2eConfig.suppressInterruptivePrompts) return;

    final current =
        await AppTrackingTransparency.trackingAuthorizationStatus;
    if (current != TrackingStatus.notDetermined) return;

    if (!context.mounted) return;

    final shouldAsk = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => const _AttPrePromptSheet(),
    );

    if (shouldAsk == true && context.mounted) {
      await AppsflyerService.instance.requestAtt();
    }
  } finally {
    AppsflyerService.instance.startSdkIfNotYetStarted();
  }
}

class _AttPrePromptSheet extends StatelessWidget {
  const _AttPrePromptSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: kPrimaryColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Help us know what\'s working',
            style: AppTypography.textLgMedium.copyWith(
              color: context.colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'On the next screen, iOS will ask if ChessEver can track activity '
            'across other apps. We use it for one thing: to credit the creator '
            'or marketing campaign that brought you here, so we know what\'s '
            'working. We don\'t sell your data and don\'t use it for anything '
            'else.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.78),
              height: 1.5,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52.h,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: kBlackColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: AppTypography.textMdMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Continue'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textPrimary.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
