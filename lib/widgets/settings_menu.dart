import 'package:flutter/material.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';

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
    return SizedBox(
      height: 144,
      child: Column(
        children: [
          // Board settings
          InkWell(
            onTap: onBoardSettingsPressed,
            child: Container(
              height: 36,
              padding: EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.shade800.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child:
                        boardSettingsIcon ??
                        Icon(Icons.grid_4x4, color: Colors.white, size: 24),
                  ),
                  SizedBox(width: 4), // Changed from 8px to 4px
                  Expanded(
                    child: Text(
                      'Board settings',
                      style: AppTypography.textMdRegular.copyWith(
                        color: Colors.white,
                      ),
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
              padding: EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.shade800.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child:
                        languageIcon ??
                        Icon(Icons.language, color: Colors.white, size: 24),
                  ),
                  SizedBox(width: 4), // Changed from 8px to 4px
                  Expanded(
                    child: Text(
                      'Language',
                      style: AppTypography.textXsRegular.copyWith(
                        color: Colors.white,
                      ),
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
              padding: EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.shade800.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child:
                        timezoneIcon ??
                        Icon(Icons.public, color: Colors.white, size: 24),
                  ),
                  SizedBox(width: 4), // Changed from 8px to 4px
                  Expanded(
                    child: Text(
                      'Set timezone',
                      style: AppTypography.textXsRegular.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Notifications toggle
          Container(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Text aligned with icons (no spacers)
                Text(
                  'Notifications',
                  style: AppTypography.textXsRegular.copyWith(
                    color: Colors.white,
                  ),
                ),
                // Custom sized switch
                SizedBox(
                  width: 28,
                  height: 17,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: Switch(
                      value: notificationsEnabled,
                      onChanged: (value) {
                        onNotificationsPressed?.call();
                      },
                      activeColor: kWhiteColor, // Circle color is white
                      activeTrackColor:
                          kPrimaryColor, // Track uses app primary color
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
