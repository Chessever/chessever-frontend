import 'dart:async';
import 'dart:io';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/services/att_prompt_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/animated_brand_logo.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/widgets/auth_state_listener.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/guest_session_gate_listener.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.forcedGuestUpgrade});

  /// Overrides the route-argument lookup for the "guest window is over" copy.
  /// Only set by tests; the app passes it as a route argument instead (see
  /// [kForcedGuestUpgradeArg]). Exists so that branch is reachable without
  /// fabricating a [ModalRoute].
  final bool? forcedGuestUpgrade;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _hasHandledAuthenticatedUser = false;

  @override
  void initState() {
    Future.microtask(() {
      ref.read(countryDropdownProvider);
    });
    // Safety net for users who reach auth without going through onboarding ATT
    // trigger. System dialog only — no explainer sheet outside onboarding.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AttPromptService.instance.ensurePrompted(context, showExplainer: false);
    });
    super.initState();
  }

  /// True when the guest window ran out and the gate routed the user here.
  bool get _isForcedGuestUpgrade {
    final override = widget.forcedGuestUpgrade;
    if (override != null) return override;
    final args = ModalRoute.of(context)?.settings.arguments;
    return args is Map && args[kForcedGuestUpgradeArg] == true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authScreenProvider);
    final isForcedGuestUpgrade = _isForcedGuestUpgrade;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Suppress showing programmatic errors to end users on auth screen
      if (state.errorMessage != null) {
        ref.read(authScreenProvider.notifier).clearError();
      }

      final user = state.user;
      if (user == null || _hasHandledAuthenticatedUser) return;
      _hasHandledAuthenticatedUser = true;

      final onboardingRepo = ref.read(onboardingRepositoryProvider);
      final hasCompleted = await onboardingRepo.isCompleted(user.id);
      if (!context.mounted) return;

      if (!hasCompleted) {
        ref.read(authScreenProvider.notifier).hideCountrySelection();
        Navigator.pushReplacementNamed(context, '/onboarding');
        return;
      }

      final navigator = Navigator.of(context);
      navigator.pushReplacementNamed('/home_screen');
      unawaited(offerNotificationsAfterSignIn(navigator));
    });

    return ScreenWrapper(
      child: Scaffold(
        key: e2eKey(E2eIds.authRoot),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Hero(tag: 'blur', child: BlurBackground()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Width and usable height decide the arrangement. A folded
                  // phone can be landscape without room for two usable panes.
                  final sideBySide =
                      constraints.maxWidth >= 720 &&
                      constraints.maxWidth > constraints.maxHeight * 1.15;
                  final buttons = _AuthButtonWidget(
                    sideBySide: sideBySide,
                    isForcedGuestUpgrade: isForcedGuestUpgrade,
                  );
                  final actions = state.isLoading
                      ? SkeletonWidget(ignoreContainers: true, child: buttons)
                      : buttons;
                  final logoHeight = ResponsiveHelper.isTablet
                      ? (sideBySide ? 180.sp : 160.sp)
                      : 156.0;
                  final logoWidth = ResponsiveHelper.isTablet
                      ? (sideBySide ? 340.sp : 300.sp)
                      : 295.0;
                  final logo = Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: logoWidth),
                        child: Hero(
                          tag: 'premium-icon',
                          child: AnimatedBrandLogo(
                            height: logoHeight,
                            width: logoWidth,
                            showWordmark: true,
                          ),
                        ),
                      ),
                    ),
                  );
                  // Preserve the existing centered logo and bottom actions
                  // whenever the window has their original vertical room.
                  if (!sideBySide && constraints.maxHeight >= 700) {
                    return Stack(
                      children: [
                        Center(child: logo),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: actions,
                        ),
                      ],
                    );
                  }
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: sideBySide
                            ? Row(
                                children: [
                                  Expanded(child: logo),
                                  Expanded(child: actions),
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: logo),
                                  actions,
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthButtonWidget extends ConsumerWidget {
  const _AuthButtonWidget({
    this.isForcedGuestUpgrade = false,
    this.sideBySide = false,
  });

  final bool sideBySide;

  /// Guest window is over — say so instead of showing bare sign-in buttons.
  final bool isForcedGuestUpgrade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = Platform.isIOS;
    final isTabletLandscape = sideBySide;
    final isTabletPortrait = ResponsiveHelper.isTablet && !sideBySide;
    final horizontalPadding = (isTabletLandscape || isTabletPortrait)
        ? 24.sp
        : 28.sp;
    final maxWidth = (isTabletLandscape || isTabletPortrait)
        ? 500.0
        : double.infinity;

    // Bottom padding for layouts that use Align(bottomCenter) - phone and tablet portrait
    final bottomPadding = isTabletLandscape
        ? 0.0
        : MediaQuery.of(context).viewPadding.bottom + 28.sp;

    final buttonColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isForcedGuestUpgrade) ...[
          Text(
            'Time to make it yours',
            textAlign: TextAlign.center,
            style: AppTypography.textLgBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'You have been playing as a guest for four weeks. '
            'Sign in to keep your players, events and analysis.',
            textAlign: TextAlign.center,
            style: AppTypography.textSmRegular.copyWith(
              color: context.textInk(0.6),
            ),
          ),
          SizedBox(height: 20.h),
        ],
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

  @override
  void initState() {
    super.initState();
    // Single controller with shorter, professional duration
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _controller.value = 1;
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const BlurBackground(),
          SlideTransition(
            position: _controller.drive(
              Tween<Offset>(begin: const Offset(0, -0.1), end: Offset.zero),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final selector = ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: _buildCountrySelector(countryState),
                  );
                  final button = _buildContinueButton(
                    context,
                    countryState,
                    notifier,
                  );
                  if (constraints.maxWidth >= 720 &&
                      constraints.maxWidth > constraints.maxHeight * 1.15) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(child: Center(child: selector)),
                              Expanded(
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 450,
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 40.sp,
                                      ),
                                      child: button,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  if (constraints.maxHeight >= 600) {
                    return Stack(
                      children: [
                        Center(child: selector),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 450),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(25),
                              ),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  20.sp,
                                  20.sp,
                                  20.sp,
                                  MediaQuery.viewPaddingOf(context).bottom +
                                      28.sp,
                                ),
                                child: button,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 450),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 24.sp,
                                vertical: 24.h,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildCountrySelector(countryState),
                                  SizedBox(height: 32.h),
                                  _buildContinueButton(
                                    context,
                                    countryState,
                                    notifier,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
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
              style: AppTypography.textMdBold.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 5.sp),
            child: countryState.when(
              loading: () => CountryDropdown(
                selectedCountryCode: '',
                onChanged: (_) {},
                hintText: 'Loading country...',
                isLoading: true,
                requireAuthToChange: false,
              ),
              error: (err, _) => AppButton(
                padding: EdgeInsets.symmetric(horizontal: 16.sp),
                text: 'Retry Getting Countries',
                onPressed: () => ref.invalidate(countryDropdownProvider),
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
        // Paper: the stacked ink halo turns into a muddy smear, so light
        // gets one tight contact shadow. Dark keeps its white glow.
        boxShadow: context.isLightTheme
            ? [
                BoxShadow(
                  color: context.colors.shadow,
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : [
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
                  color: kBlackColor.withValues(alpha: 0.2),
                  blurRadius: 15,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: countryState.maybeWhen(
          loading: () => null,
          orElse: () => () async {
            await _dismissWithAnimation();
            if (!context.mounted) return;

            notifier.hideCountrySelection();
            Navigator.of(context).pop();
            if (!widget.isHamburgerMode) {
              final onboardingRepo = ref.read(onboardingRepositoryProvider);
              final userId = Supabase.instance.client.auth.currentUser?.id;
              final hasCompleted = await onboardingRepo.isCompleted(userId);
              if (!context.mounted) return;
              final targetRoute = hasCompleted ? '/home_screen' : '/onboarding';
              Navigator.pushReplacementNamed(context, targetRoute);
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
