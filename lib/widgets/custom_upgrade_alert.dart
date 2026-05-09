import 'dart:io';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

/// Custom upgrade messages for localization support
class CustomUpgraderMessages extends UpgraderMessages {
  @override
  String get title => 'Update Available';

  @override
  String get body =>
      'A new version of ChessEver is available. Update now to get the latest features and improvements.';

  @override
  String get buttonTitleIgnore => 'Skip This Version';

  @override
  String get buttonTitleLater => 'Remind Me Later';

  @override
  String get buttonTitleUpdate => 'Update Now';

  @override
  String get prompt => '';
}

/// Custom upgrade alert widget wrapper for ChessEver
/// Uses the standard UpgradeAlert with custom theming
class CustomUpgradeAlert extends StatelessWidget {
  final Widget child;
  final Upgrader upgrader;
  final GlobalKey<NavigatorState>? navigatorKey;

  const CustomUpgradeAlert({
    super.key,
    required this.child,
    required this.upgrader,
    this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    // Wrap with custom theme for the dialog
    return Theme(
      data: Theme.of(context).copyWith(
        // Customize dialog theme
        dialogTheme: DialogThemeData(
          backgroundColor: context.colors.popup,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.sp),
          ),
          titleTextStyle: AppTypography.textXlBold.copyWith(color: kWhiteColor),
          contentTextStyle: AppTypography.textSmRegular.copyWith(
            color: context.colors.textPrimaryMuted,
          ),
        ),
        // Customize button theme
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kWhiteColor,
            padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 24.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.sp),
            ),
            textStyle: AppTypography.textMdMedium,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryColor,
            foregroundColor: kWhiteColor,
            padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 24.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.sp),
            ),
            textStyle: AppTypography.textMdBold,
            elevation: 0,
          ),
        ),
      ),
      child: UpgradeAlert(
        upgrader: upgrader,
        navigatorKey: navigatorKey,
        showIgnore: false,
        showLater: false,
        shouldPopScope:
            () => kDebugMode, // Block back button in release, allow in debug
        barrierDismissible: kDebugMode, // Allow tap outside in debug only
        dialogStyle:
            Platform.isIOS
                ? UpgradeDialogStyle.cupertino
                : UpgradeDialogStyle.material,
        cupertinoButtonTextStyle:
            Platform.isIOS
                ? AppTypography.textMdMedium.copyWith(color: kPrimaryColor)
                : null,
        child: child,
      ),
    );
  }
}
