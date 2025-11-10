import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter_svg/svg.dart';

class SettingsMenu extends StatelessWidget {
  final bool isSmallScreen;
  final bool isLargeScreen;
  final VoidCallback? onBoardSettingsPressed;
  final Widget? boardSettingsIcon;

  const SettingsMenu({
    super.key,
    this.isSmallScreen = false,
    this.isLargeScreen = false,
    this.onBoardSettingsPressed,
    this.boardSettingsIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 12.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 10.h),
          Container(
            height: 5,
            width: 40,
            decoration: BoxDecoration(
              color: kWhiteColor,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          SizedBox(height: 15),
          Text(
            'Settings',
            style: AppTypography.textLgMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 25.h),
          // Board settings
          InkWell(
            onTap: onBoardSettingsPressed != null
                ? () {
                    HapticFeedbackService.navigation();
                    onBoardSettingsPressed!();
                  }
                : null,
            child: Container(
              height: 36,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24.w,
                    child:
                        boardSettingsIcon ??
                        Icon(Icons.grid_4x4, color: Colors.white, size: 12.ic),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child: Text(
                      'Board settings',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: SvgPicture.asset(
                      SvgAsset.right_arrow,
                      height: 24.h,
                      width: 24.w,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 15.h),
        ],
      ),
    );
  }
}
