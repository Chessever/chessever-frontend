import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter_svg/svg.dart';

class SettingsMenu extends StatelessWidget {
  final bool notificationsEnabled;
  final String languageSubtitle;
  final String timezoneSubtitle;
  final bool isSmallScreen;
  final bool isLargeScreen;
  final VoidCallback? onBoardSettingsPressed;
  final VoidCallback? onLanguagePressed;
  final VoidCallback? onTimezonePressed;
  final VoidCallback? onNotificationsPressed;
  final Widget? boardSettingsIcon;
  final Widget? languageIcon;
  final Widget? timezoneIcon;

  const SettingsMenu({
    Key? key,
    required this.notificationsEnabled,
    this.languageSubtitle = "English",
    this.timezoneSubtitle = "UTC+0",
    this.isSmallScreen = false,
    this.isLargeScreen = false,
    this.onBoardSettingsPressed,
    this.onLanguagePressed,
    this.onTimezonePressed,
    this.onNotificationsPressed,
    this.boardSettingsIcon,
    this.languageIcon,
    this.timezoneIcon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Fixed height of 144px (36px × 4 menu items)
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 12.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,

        children: [
          Text(
            'Settings',
            style: AppTypography.textLgMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 20.h),
          // Board settings
          InkWell(
            onTap: onBoardSettingsPressed,
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.shade800.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
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
                  SizedBox(width: 4.w), // Changed from 8px to 4px
                  Expanded(
                    child: Text(
                      'Board settings',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                      ),
                      // style: TextStyle(
                      //   fontFamily: 'InterDisplay',
                      //   fontSize: 12,
                      //   fontWeight: FontWeight.w400,
                      //   color: kWhiteColor,
                      // ),
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

          // Language
          InkWell(
            onTap: onLanguagePressed,
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.shade800.withOpacity(
                      0.15,
                    ), // Reduced opacity from 0.3 to 0.15
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24.w,
                    child:
                        languageIcon ??
                        Icon(Icons.language, color: kWhiteColor, size: 20),
                  ),
                  SizedBox(width: 4), // Changed from 8px to 4px
                  Expanded(
                    child: Text(
                      'Language',
                      style: AppTypography.textMdMedium.copyWith(
                        color: Colors.white,
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

          // Set timezone
          InkWell(
            onTap: onTimezonePressed,
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.shade800.withOpacity(
                      0.15,
                    ), // Reduced opacity from 0.3 to 0.15
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24.w,
                    child:
                        timezoneIcon ??
                        Icon(Icons.public, color: Colors.white, size: 12.ic),
                  ),
                  SizedBox(width: 4), // Changed from 8px to 4px
                  Expanded(
                    child: Text(
                      'Set timezone',
                      style: AppTypography.textMdMedium.copyWith(
                        color: Colors.white,
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

          // Notifications toggle
          Container(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Text aligned with icons (no spacers)
                Text(
                  'Notifications',
                  style: AppTypography.textMdMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
                // Custom sized switch
                SizedBox(
                  width: 34,
                  height: 20,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: Switch(
                      value: notificationsEnabled,
                      onChanged: (value) {
                        onNotificationsPressed?.call();
                      },
                      activeColor: kWhiteColor,
                      // Circle color is white
                      activeTrackColor: kPrimaryColor,
                      // Track uses app primary color
                      inactiveThumbColor: kWhiteColor,
                      inactiveTrackColor: Colors.grey.withOpacity(0.5),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
