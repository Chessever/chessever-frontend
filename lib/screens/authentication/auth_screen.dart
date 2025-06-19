import 'dart:io';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isApple = Platform.isIOS;
    return ScreenWrapper(
      child: Scaffold(
        body: Stack(
          children: [
            Hero(tag: 'blur', child: BlurBackground()),
            Positioned(
              top: (MediaQuery.of(context).size.height / 2) - 69,
              left: (MediaQuery.of(context).size.width / 2) - 60,
              child: Column(
                children: [
                  Hero(
                    tag: 'premium-icon',
                    child: Image.asset(
                      PngAsset.premiumIcon,
                      height: 120,
                      width: 120,
                    ),
                  ),
                  Image.asset(PngAsset.chesseverIcon, height: 18),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewPadding.bottom + 28,
                  left: 28,
                  right: 28,
                ),
                child:
                    isApple
                        ? AuthButton(
                          signInTitle: 'Continue with Apple',
                          svgIconPath: SvgAsset.appleIcon,
                          onPressed: () {
                            showAlertModal(
                              context: context,
                              child: _CountryDropdownWidget(),
                            );
                          },
                        )
                        : AuthButton(
                          signInTitle: 'Continue with Google',
                          svgIconPath: SvgAsset.googleIcon,
                          onPressed: () {
                            showAlertModal(
                              context: context,
                              child: _CountryDropdownWidget(),
                            );
                          },
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryDropdownWidget extends StatelessWidget {
  const _CountryDropdownWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        BackDropFilterWidget(),
        Positioned(
          top: MediaQuery.of(context).size.height / 2 - 60,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Select Your Country',
                  style: AppTypography.textSmBold,
                ),
              ),
              SizedBox(height: 4),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 48),
                width: MediaQuery.of(context).size.width,
                child: CountryDropdown(
                  onChanged: (_) {
                    Navigator.of(context).pop();
                    Navigator.pushReplacementNamed(
                      context,
                      '/home_screen',
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
