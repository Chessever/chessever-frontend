import 'dart:io';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/screens/authentication/auth_screen_state.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  @override
  void initState() {
    Future.microtask(() async {
      await ref.read(countryDropdownProvider);
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authScreenProvider);
    final isTablet = ResponsiveHelper.isTablet;
    final isLandscape = ResponsiveHelper.isLandscape;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Suppress showing programmatic errors to end users on auth screen
      if (state.errorMessage != null) {
        ref.read(authScreenProvider.notifier).clearError();
        return;
      }

      final user = state.user;
      if (user == null) return;

      // Only navigate for non-anonymous users (OAuth users)
      // Anonymous users are handled by the "Continue as Guest" button directly
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      if (supabaseUser?.isAnonymous == true) return;

      final onboardingRepo = ref.read(onboardingRepositoryProvider);
      final hasCompleted = await onboardingRepo.isCompleted(user.id);
      if (!mounted) return;

      if (!hasCompleted) {
        ref.read(authScreenProvider.notifier).hideCountrySelection();
        Navigator.pushReplacementNamed(context, '/onboarding');
        return;
      }

      Navigator.pushReplacementNamed(context, '/home_screen');
    });

    // Tablet landscape: side-by-side layout
    if (isTablet && isLandscape) {
      return ScreenWrapper(
        child: Scaffold(
          key: e2eKey(E2eIds.authRoot),
          body: Stack(
            children: [
              const Hero(tag: 'blur', child: BlurBackground()),
              Row(
                children: [
                  // Left side: Logo centered
                  Expanded(
                    child: Center(
                      child: Hero(
                        tag: 'premium-icon',
                        child: Image.asset(
                          PngAsset.chesseverIcon,
                          height: 180.sp,
                          width: 340.sp,
                          cacheWidth:
                              (340 * MediaQuery.devicePixelRatioOf(context))
                                  .toInt(),
                        ),
                      ),
                    ),
                  ),
                  // Right side: Auth buttons centered
                  Expanded(
                    child: Center(
                      child:
                          state.isLoading
                              ? SkeletonWidget(
                                ignoreContainers: true,
                                child: _AuthButtonWidget(
                                  state: state,
                                  isTabletLandscape: true,
                                ),
                              )
                              : _AuthButtonWidget(
                                state: state,
                                isTabletLandscape: true,
                              ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Tablet portrait: same structure as phone but with tablet sizing
    if (isTablet) {
      return ScreenWrapper(
        child: Scaffold(
          key: e2eKey(E2eIds.authRoot),
          body: Stack(
            children: [
              const Hero(tag: 'blur', child: BlurBackground()),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Hero(
                      tag: 'premium-icon',
                      child: Image.asset(
                        PngAsset.chesseverIcon,
                        height: 160.sp,
                        width: 300.sp,
                        cacheWidth:
                            (300 * MediaQuery.devicePixelRatioOf(context))
                                .toInt(),
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child:
                    state.isLoading
                        ? SkeletonWidget(
                          ignoreContainers: true,
                          child: _AuthButtonWidget(
                            state: state,
                            isTabletPortrait: true,
                          ),
                        )
                        : _AuthButtonWidget(
                          state: state,
                          isTabletPortrait: true,
                        ),
              ),
            ],
          ),
        ),
      );
    }

    // Phone: stacked layout with bottom buttons
    return ScreenWrapper(
      child: Scaffold(
        key: e2eKey(E2eIds.authRoot),
        body: Stack(
          children: [
            // Background blur layer
            const Hero(tag: 'blur', child: BlurBackground()),

            // Centered Column with Icon and Text
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hero(
                    tag: 'premium-icon',
                    child: Image.asset(
                      PngAsset.chesseverIcon,
                      height: 156,
                      width: 295,
                      cacheWidth:
                          (295 * MediaQuery.devicePixelRatioOf(context))
                              .toInt(),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Auth Button
            Align(
              alignment: Alignment.bottomCenter,
              child:
                  state.isLoading
                      ? SkeletonWidget(
                        ignoreContainers: true,
                        child: _AuthButtonWidget(state: state),
                      )
                      : _AuthButtonWidget(state: state),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthButtonWidget extends ConsumerWidget {
  const _AuthButtonWidget({
    required this.state,
    this.isTabletLandscape = false,
    this.isTabletPortrait = false,
    super.key,
  });

  final AuthScreenState state;
  final bool isTabletLandscape;
  final bool isTabletPortrait;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = Platform.isIOS;

    // Tablet landscape: centered in its container (parent handles centering)
    // Tablet portrait & phone: positioned at bottom via Align(bottomCenter)
    final horizontalPadding =
        (isTabletLandscape || isTabletPortrait) ? 24.sp : 28.sp;
    final maxWidth =
        (isTabletLandscape || isTabletPortrait) ? 500.0 : double.infinity;

    // Bottom padding for layouts that use Align(bottomCenter) - phone and tablet portrait
    final bottomPadding =
        isTabletLandscape
            ? 0.0
            : MediaQuery.of(context).viewPadding.bottom + 28.sp;

    final buttonColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Show both buttons on iOS, only Google on Android
        if (isIos) ...[
          AuthButton(
            signInTitle: 'Continue with Apple',
            svgIconPath: SvgAsset.appleIcon,
            onPressed: () async {
              await ref.read(authScreenProvider.notifier).signInWithApple();
            },
          ),
          SizedBox(height: 12.h),
        ],
        AuthButton(
          signInTitle: 'Continue with Google',
          svgIconPath: SvgAsset.googleIcon,
          onPressed: () async {
            await ref.read(authScreenProvider.notifier).signInWithGoogle();
          },
        ),
        SizedBox(height: 12.h),
        TextButton(
          onPressed: () async {
            final appUser =
                await ref.read(authScreenProvider.notifier).signInAsGuest();

            if (!context.mounted || appUser == null || !appUser.isAnonymous)
              return;

            final onboardingRepo = ref.read(onboardingRepositoryProvider);
            final hasCompleted = await onboardingRepo.isCompleted(appUser.id);

            if (!context.mounted) return;
            Navigator.pushNamedAndRemoveUntil(
              context,
              hasCompleted ? '/home_screen' : '/onboarding',
              (_) => false,
            );
            ref.read(authScreenProvider.notifier).reset();
          },
          child: Text(
            'Continue as Guest',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.7),
              decoration: TextDecoration.underline,
              decorationColor: context.colors.textPrimary.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );

    // Tablet landscape: use Center (parent is Center in Row)
    if (isTabletLandscape) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: buttonColumn,
          ),
        ),
      );
    }

    // Phone: simple padding, buttons stretch to fill width
    if (!isTabletPortrait) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: bottomPadding,
          left: horizontalPadding,
          right: horizontalPadding,
        ),
        child: buttonColumn,
      );
    }

    // Tablet portrait: use Row to center with max width constraint
    return Padding(
      padding: EdgeInsets.only(
        bottom: bottomPadding,
        left: horizontalPadding,
        right: horizontalPadding,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth - (horizontalPadding * 2),
              ),
              child: buttonColumn,
            ),
          ),
        ],
      ),
    );
  }
}

class CountryPickerWidget extends ConsumerStatefulWidget {
  const CountryPickerWidget({this.isHamburgerMode = false, super.key});

  final bool isHamburgerMode;

  @override
  ConsumerState<CountryPickerWidget> createState() =>
      _CountryPickerWidgetState();
}

class _CountryPickerWidgetState extends ConsumerState<CountryPickerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // Single controller with shorter, professional duration
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Subtle fade animation
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // Minimal slide animation from top
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Start animation
    _controller.forward();
  }

  Future<void> _dismissWithAnimation() async {
    await _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(authScreenProvider.notifier);
    final countryState = ref.watch(countryDropdownProvider);
    final isTablet = ResponsiveHelper.isTablet;
    final isLandscape = ResponsiveHelper.isLandscape;

    // Max width for content on tablets
    const maxContentWidth = 450.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: GestureDetector(
        onTap: widget.isHamburgerMode ? Navigator.of(context).pop : null,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Tablet landscape: side-by-side layout
            if (isTablet && isLandscape) {
              return Stack(
                children: [
                  Opacity(
                    opacity: _fadeAnimation.value,
                    child: BlurBackground(),
                  ),
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Row(
                        children: [
                          // Left side: Country selection
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: maxContentWidth,
                                ),
                                child: _buildCountrySelector(countryState),
                              ),
                            ),
                          ),
                          // Right side: Continue button
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: maxContentWidth,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 40.sp,
                                  ),
                                  child: _buildContinueButton(
                                    context,
                                    countryState,
                                    notifier,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            // Phone and tablet portrait: stacked layout
            return Stack(
              children: [
                // Background content with subtle fade
                Opacity(opacity: _fadeAnimation.value, child: BlurBackground()),

                // Main content with minimal slide
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: maxContentWidth,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [_buildCountrySelector(countryState)],
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom button area with fade-in
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: maxContentWidth,
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(25),
                          ),
                          child: Container(
                            padding: EdgeInsets.fromLTRB(
                              20.sp,
                              20.sp,
                              20.sp,
                              MediaQuery.of(context).viewPadding.bottom + 28.sp,
                            ),
                            child: _buildContinueButton(
                              context,
                              countryState,
                              notifier,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCountrySelector(AsyncValue<Country> countryState) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 40.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 10.sp),
            child: Text(
              'Select your Country',
              style: AppTypography.textMdBold.copyWith(color: context.colors.textPrimary),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 5.sp),
            child: countryState.when(
              loading:
                  () => CountryDropdown(
                    selectedCountryCode: '',
                    onChanged: (_) {},
                    hintText: 'Loading country...',
                    isLoading: true,
                    requireAuthToChange: false,
                  ),
              error:
                  (err, _) => AppButton(
                    padding: EdgeInsets.symmetric(horizontal: 16.sp),
                    text: 'Retry Getting Countries',
                    onPressed: () => ref.invalidate(countryDropdownProvider),
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
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton(
    BuildContext context,
    AsyncValue<Country> countryState,
    AuthScreenNotifier notifier,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: context.colors.textPrimary.withValues(alpha: 0.8),
            blurRadius: 8,
            spreadRadius: 2,
            offset: const Offset(-1, 0),
          ),
          BoxShadow(
            color: context.colors.textPrimary.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: context.colors.textPrimary.withValues(alpha: 0.3),
            blurRadius: 35,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: kBlackColor.withOpacity(0.2),
            blurRadius: 15,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: countryState.maybeWhen(
          loading: () => null,
          orElse:
              () => () async {
                await _dismissWithAnimation();
                if (mounted) {
                  notifier.hideCountrySelection();
                  Navigator.of(context).pop();
                  if (!widget.isHamburgerMode) {
                    final onboardingRepo = ref.read(
                      onboardingRepositoryProvider,
                    );
                    final userId =
                        Supabase.instance.client.auth.currentUser?.id;
                    final hasCompleted = await onboardingRepo.isCompleted(
                      userId,
                    );
                    if (!mounted) return;
                    final targetRoute =
                        hasCompleted ? '/home_screen' : '/onboarding';
                    Navigator.pushReplacementNamed(context, targetRoute);
                  }
                }
              },
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: countryState.maybeWhen(
            loading: () => context.colors.textPrimary.withValues(alpha: 0.4),
            orElse: () => context.colors.textPrimary,
          ),
          foregroundColor: context.colors.textInverse,
          padding: EdgeInsets.symmetric(vertical: 16.sp),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.br),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: Text(
          'Continue',
          style: AppTypography.textLgMedium.copyWith(
            color: context.colors.textInverse,
          ),
        ),
      ),
    );
  }
}
