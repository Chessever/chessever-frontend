import 'dart:io';
import 'dart:ui';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen_state.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
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
  Widget build(BuildContext context) {
    final state = ref.watch(authScreenProvider);

    // Listen for state changes
    ref.listen<AuthScreenState>(authScreenProvider, (previous, current) {
      // Show country selection modal after successful sign in
      if (current.showCountrySelection && current.user != null) {
        _showCountrySelectionModal();
      }

      // Show error message if there's an error
      if (current.errorMessage != null) {
        _showErrorDialog(current.errorMessage!);
      }

      //todo: setup country code Here
      String? countryCode = null;
      // Navigate to home if user has country selected
      if (current.user != null &&
          countryCode != null &&
          countryCode.isNotEmpty) {
        Navigator.pushReplacementNamed(context, '/home_screen');
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
                      height: 120,
                      width: 295,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Follow Chess Better.",
                    style: AppTypography.textXsRegular.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
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
      child: _AuthCountryDropdownWidget(),
    );
  }

  void _showErrorDialog(String errorMessage) {
    //todo: Error Dialod
    showDialog(
      context: context,
      builder:
          (cxt) => AlertDialog(
            backgroundColor: kBackgroundColor,
            title: Text(
              'Sign In Error',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
            content: Text(
              errorMessage,
              style: AppTypography.textXsMedium.copyWith(color: kRedColor),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(authScreenProvider.notifier).clearError();
                },
                child: const Text('OK'),
              ),
            ],
          ),
    );
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
      child: AuthButton(
        signInTitle: isIos ? 'Continue with Apple' : 'Continue with Google',
        svgIconPath: isIos ? SvgAsset.appleIcon : SvgAsset.googleIcon,
        onPressed: () async {
          if (isIos) {
            await ref.read(authScreenProvider.notifier).signInWithApple();
          } else {
            await ref.read(authScreenProvider.notifier).signInWithGoogle();
          }
        },
      ),
    );
  }
}

class _AuthCountryDropdownWidget extends ConsumerWidget {
  const _AuthCountryDropdownWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(authScreenProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          // Background content
          BlurBackground(),

          // Main content
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Country selection box (centered)
              Container(
                margin: EdgeInsets.symmetric(horizontal: 40.sp),

                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(horizontal: 10.sp),
                      child: Text(
                        'Select your Country',
                        style: AppTypography.textMdMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),

                    // Dropdown
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.sp,
                        vertical: 5.sp,
                      ),
                      child: CountryDropdown(
                        selectedCountryCode: 'US',
                        onChanged: (Country country) async {
                          await ref
                              .read(countryDropdownProvider.notifier)
                              .selectCountry(country.countryCode);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Blurred bottom button area
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
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
                    // Enhanced glow effect with multiple shadows
                    boxShadow: [
                      // Inner glow
                      BoxShadow(
                        color: kWhiteColor.withOpacity(0.8),
                        blurRadius: 8,
                        spreadRadius: 2,
                        offset: Offset(-1, 0),
                      ),
                      // // Outer glow - larger
                      BoxShadow(
                        color: kWhiteColor.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: Offset(0, 2),
                      ),
                      // Additional outer glow for stronger effect
                      BoxShadow(
                        color: kWhiteColor.withOpacity(0.3),
                        blurRadius: 35,
                        spreadRadius: 2,
                        offset: Offset(0, 4),
                      ),
                      // Subtle bottom shadow for depth
                      BoxShadow(
                        color: kBlackColor.withOpacity(0.2),
                        blurRadius: 15,
                        spreadRadius: 1,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      notifier.hideCountrySelection();
                      Navigator.of(context).pop();
                      Navigator.pushReplacementNamed(context, '/home_screen');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kWhiteColor,
                      foregroundColor: kBlackColor,
                      padding: EdgeInsets.symmetric(vertical: 16.sp),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.br),
                      ),
                      elevation: 0,
                      // Remove default elevation since we're using custom shadows
                      shadowColor: Colors.transparent, // Remove default shadow
                    ),
                    child: Text('Continue', style: AppTypography.textLgRegular),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
