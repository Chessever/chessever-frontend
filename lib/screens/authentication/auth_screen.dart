import 'dart:io';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen_state.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.showCountrySelection && state.user != null) {
        _showCountrySelectionModal();
      } else if (state.errorMessage != null) {
        _showErrorDialog(state.errorMessage!);
      } else if (ref.read(countryDropdownProvider).value != null &&
          state.user != null) {
        if (ref.read(countryDropdownProvider).value?.countryCode != null) {
          Navigator.pushReplacementNamed(context, '/home_screen');
        }
      }
    });

    return ScreenWrapper(
      child: Scaffold(
        body: Stack(
          children: [
            // Background blur layer
            const Hero(tag: 'blur', child: BlurBackground()),

            // Centered Column with Icon and Text
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Hero(
                    tag: 'premium-icon',
                    child: Image(
                      image: AssetImage(PngAsset.chesseverIcon),
                      height: 156,
                      width: 295,
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

  void _showCountrySelectionModal() {
    showAlertModal(
      context: context,
      barrierDismissible: false,
      horizontalPadding: 0,
      verticalPadding: 0,
      child: CountryPickerWidget(),
    );
  }

  void _showErrorDialog(String errorMessage) {
    showAlertModal<void>(
      context: context,
      horizontalPadding: 40.sp,
      verticalPadding: 0,
      barrierDismissible: true,
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 340.w),
          decoration: BoxDecoration(
            color: kPopUpColor,
            borderRadius: BorderRadius.circular(20.br),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: EdgeInsets.all(24.sp),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error Icon
              Container(
                width: 56.w,
                height: 56.h,
                decoration: BoxDecoration(
                  color: kRedColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  color: kRedColor,
                  size: 32.sp,
                ),
              ),
              SizedBox(height: 16.h),

              // Title
              Text(
                'Sign In Failed',
                style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8.h),

              // Error Message
              Text(
                errorMessage,
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24.h),

              // Try Again Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kWhiteColor,
                    foregroundColor: kBlackColor,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.br),
                    ),
                    elevation: 0,
                  ),
                  child: Text('Try Again', style: AppTypography.textSmBold),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (!mounted) return;
      ref.read(authScreenProvider.notifier).clearError();
    });
  }
}

class _AuthButtonWidget extends ConsumerWidget {
  const _AuthButtonWidget({required this.state, super.key});

  final AuthScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = Platform.isIOS;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewPadding.bottom + 28.sp,
        left: 28.sp,
        right: 28.sp,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: GestureDetector(
        onTap: widget.isHamburgerMode ? Navigator.of(context).pop : null,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              children: [
                // Background content with subtle fade
                Opacity(opacity: _fadeAnimation.value, child: BlurBackground()),

                // Main content with minimal slide
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Country selection box (centered)
                        Container(
                          margin: EdgeInsets.symmetric(horizontal: 40.sp),
                          child: Column(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10.sp,
                                ),
                                child: Text(
                                  'Select your Country',
                                  style: AppTypography.textMdBold.copyWith(
                                    color: kWhiteColor,
                                  ),
                                ),
                              ),

                              // Dropdown
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10.sp,
                                  vertical: 5.sp,
                                ),
                                child: countryState.when(
                                  loading:
                                      () => CountryDropdown(
                                        selectedCountryCode: '',
                                        onChanged: (_) {},
                                        hintText: 'Loading country...',
                                        isLoading: true,
                                      ),
                                  error:
                                      (err, _) => AppButton(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16.sp,
                                        ),
                                        text: 'Retry Getting Countries',
                                        onPressed: () {
                                          ref.invalidate(
                                            countryDropdownProvider,
                                          );
                                        },
                                      ),
                                  data: (country) {
                                    return CountryDropdown(
                                      selectedCountryCode: country.countryCode,
                                      onChanged: (Country newCountry) async {
                                        await ref
                                            .read(
                                              countryDropdownProvider.notifier,
                                            )
                                            .selectCountry(
                                              newCountry.countryCode,
                                            );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: kWhiteColor.withOpacity(0.8),
                                blurRadius: 8,
                                spreadRadius: 2,
                                offset: const Offset(-1, 0),
                              ),
                              BoxShadow(
                                color: kWhiteColor.withOpacity(0.5),
                                blurRadius: 20,
                                spreadRadius: 2,
                                offset: const Offset(0, 2),
                              ),
                              BoxShadow(
                                color: kWhiteColor.withOpacity(0.3),
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
                                        Navigator.pushReplacementNamed(
                                          context,
                                          '/home_screen',
                                        );
                                      }
                                    }
                                  },
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: countryState.maybeWhen(
                                loading: () => kWhiteColor.withOpacity(0.4),
                                orElse: () => kWhiteColor,
                              ),
                              foregroundColor: kBlackColor,
                              padding: EdgeInsets.symmetric(vertical: 16.sp),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.br),
                              ),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                            ),
                            child: Text(
                              'Continue',
                              style: AppTypography.textLgMedium,
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
}
