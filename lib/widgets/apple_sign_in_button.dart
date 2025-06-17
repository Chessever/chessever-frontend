import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import '../utils/app_typography.dart';

class AppleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final double height;
  final double? width;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const AppleSignInButton({
    super.key,
    this.onPressed,
    this.height = 48, // 48px height as specified
    this.width,
    this.borderRadius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width ?? MediaQuery.of(context).size.width,
      child: ElevatedButton(
        onPressed:
            onPressed ??
            () {
              // Navigate to the player list screen when the button is pressed
              Navigator.of(context).pushNamed('/playerList');
            },
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.all<Color>(kWhiteColor),
          // Pure white with no opacity
          foregroundColor: MaterialStateProperty.all<Color>(kBackgroundColor),
          elevation: MaterialStateProperty.all<double>(0),
          padding: MaterialStateProperty.all<EdgeInsetsGeometry>(padding),
          shape: MaterialStateProperty.all<RoundedRectangleBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
            ),
          ),
          // Ensure the button doesn't change colors when pressed
          overlayColor: MaterialStateProperty.all<Color>(Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgWidget(
              SvgAsset.appleIcon,
              height: 24,
              width: 24,
              colorFilter: ColorFilter.mode(
                Colors.black, // Black Apple logo
                BlendMode.srcIn,
              ),
              fallback: Icon(Icons.apple, size: 24, color: kBackgroundColor),
            ),
            const SizedBox(width: 12),
            Text(
              'Continue with Apple',
              style: AppTypography.textLgMedium.copyWith(
                color: kBackgroundColor, // Black text
              ),
            ),
          ],
        ),
      ),
    );
  }
}
