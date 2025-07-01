import 'dart:io';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen_state.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
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
      if (current.showCountrySelection && !current.isLoading) {
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
            Hero(tag: 'blur', child: BlurBackground()),
            Positioned(
              top: (MediaQuery.of(context).size.height / 2) - 60.h,
              left: (MediaQuery.of(context).size.width / 2) - 60.w,
              child: Column(
                children: [
                  Hero(
                    tag: 'premium-icon',
                    child: Image.asset(
                      PngAsset.premiumIcon,
                      height: 120.h,
                      width: 120.w,
                    ),
                  ),
                  Image.asset(PngAsset.chesseverIcon, height: 18.h),
                ],
              ),
            ),
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
    // showDialog(
    //   context: context,
    //   builder:
    //       (cxt) => AlertDialog(
    //         backgroundColor: kBackgroundColor,
    //         title: Text(
    //           'Sign In Error',
    //           style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
    //         ),
    //         content: Text(
    //           errorMessage,
    //           style: AppTypography.textXsMedium.copyWith(color: kRedColor),
    //         ),
    //         actions: [
    //           TextButton(
    //             onPressed: () {
    //               Navigator.of(context).pop();
    //               ref.read(authScreenProvider.notifier).clearError();
    //             },
    //             child: const Text('OK'),
    //           ),
    //         ],
    //       ),
    // );
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
    final state = ref.watch(authScreenProvider);
    final notifier = ref.read(authScreenProvider.notifier);

    return Stack(
      alignment: Alignment.center,
      children: [
        BackDropFilterWidget(),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 48.sp),
              child: Text(
                'Select Your Country',
                style: AppTypography.textSmBold,
              ),
            ),
            SizedBox(height: 4.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 48.sp),
              width: MediaQuery.of(context).size.width,
              //todo: Get and Set CountryCode here
              child: CountryDropdown(
                selectedCountryCode: 'US',
                onChanged: (countryCode) async {
                  ref
                      .read(countryDropdownProvider.notifier)
                      .selectCountry(countryCode);
                  // Hide country selection modal
                  notifier.hideCountrySelection();

                  // Close modal and navigate to home
                  Navigator.of(context).pop();
                  Navigator.pushReplacementNamed(context, '/home_screen');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
