import 'dart:io';

import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/widgets/blur_background.dart';
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
                            Navigator.pushReplacementNamed(
                              context,
                              '/select_country_screen',
                            );
                          },
                        )
                        : AuthButton(
                          signInTitle: 'Continue with Google',
                          svgIconPath: SvgAsset.googleIcon,
                          onPressed: () {
                            Navigator.pushReplacementNamed(
                              context,
                              '/select_country_screen',
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
