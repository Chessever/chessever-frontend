import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingsMenu extends ConsumerWidget {
  final bool isSmallScreen;
  final bool isLargeScreen;
  final VoidCallback? onBoardSettingsPressed;
  final VoidCallback? onNotificationSettingsPressed;
  final VoidCallback? onDeleteAccountPressed;
  final Widget? boardSettingsIcon;
  final Widget? notificationSettingsIcon;

  const SettingsMenu({
    super.key,
    this.isSmallScreen = false,
    this.isLargeScreen = false,
    this.onBoardSettingsPressed,
    this.onNotificationSettingsPressed,
    this.onDeleteAccountPressed,
    this.boardSettingsIcon,
    this.notificationSettingsIcon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget buildMenuIcon(Widget? icon, IconData fallback) {
      final Widget resolved = icon ?? Icon(fallback, color: Colors.white, size: 16.ic);
      return Center(
        child: SizedBox.square(
          dimension: 16.ic,
          child: FittedBox(
            fit: BoxFit.contain,
            child: resolved,
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 12.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 10.h),
          Container(
            height: 5.h,
            width: 40.w,
            decoration: BoxDecoration(
              color: kWhiteColor,
              borderRadius: BorderRadius.circular(20.br),
            ),
          ),
          SizedBox(height: 15.h),
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
            child: SizedBox(
              height: 36.h,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24.w,
                    child: buildMenuIcon(boardSettingsIcon, Icons.grid_4x4),
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
                    width: 36.w,
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
          // Notification settings
          InkWell(
            onTap: onNotificationSettingsPressed != null
                ? () {
                    HapticFeedbackService.navigation();
                    onNotificationSettingsPressed!();
                  }
                : null,
            child: SizedBox(
              height: 36.h,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24.w,
                    child: buildMenuIcon(
                      notificationSettingsIcon,
                      Icons.notifications_active_outlined,
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child: Text(
                      'Notification settings',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36.w,
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
          SizedBox(height: 18.h),

          // Delete Account
          if (onDeleteAccountPressed != null)
            InkWell(
              onTap: () {
                HapticFeedbackService.navigation();
                onDeleteAccountPressed!();
              },
              child: SizedBox(
                height: 36.h,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24.w,
                      child: Icon(Icons.delete_forever, color: kRedColor, size: 20.ic),
                    ),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: Text(
                        'Delete Account',
                        style: AppTypography.textMdMedium.copyWith(
                          color: kRedColor,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36.w,
                      child: SvgPicture.asset(
                        SvgAsset.right_arrow,
                        height: 24.h,
                        width: 24.w,
                        colorFilter: const ColorFilter.mode(kRedColor, BlendMode.srcIn),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (onDeleteAccountPressed != null) SizedBox(height: 15.h),
        ],
      ),
    );
  }
}
