import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/providers/notifications_settings_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';

class SettingsMenu extends ConsumerWidget {
  final bool isSmallScreen;
  final bool isLargeScreen;
  final VoidCallback? onBoardSettingsPressed;
  final VoidCallback? onDeleteAccountPressed;
  final Widget? boardSettingsIcon;

  const SettingsMenu({
    super.key,
    this.isSmallScreen = false,
    this.isLargeScreen = false,
    this.onBoardSettingsPressed,
    this.onDeleteAccountPressed,
    this.boardSettingsIcon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pushSettings = ref.watch(notificationsSettingsProvider);
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final prefs = prefsAsync.valueOrNull ?? NotificationPreferences.defaults;
    final prefsLoading = prefsAsync.isLoading;
    final pushEnabled = pushSettings.enabled;

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
          // Notifications
          _SectionLabel(title: 'Notifications'),
          _ToggleRow(
            title: 'Push notifications',
            value: pushEnabled,
            onChanged: (value) async {
              HapticFeedbackService.navigation();
              await ref
                  .read(notificationsSettingsProvider.notifier)
                  .setEnabled(value);
            },
          ),
          SizedBox(height: 8.h),
          _ToggleRow(
            title: 'Favorite players',
            value: prefs.favoritePlayerAlerts,
            onChanged: (!pushEnabled || prefsLoading)
                ? null
                : (value) async {
                    await ref
                        .read(notificationPreferencesProvider.notifier)
                        .setFavoritePlayerAlerts(value);
                  },
          ),
          SizedBox(height: 6.h),
          _ToggleRow(
            title: 'Favorite events',
            value: prefs.favoriteEventAlerts,
            onChanged: (!pushEnabled || prefsLoading)
                ? null
                : (value) async {
                    await ref
                        .read(notificationPreferencesProvider.notifier)
                        .setFavoriteEventAlerts(value);
                  },
          ),
          SizedBox(height: 6.h),
          _ToggleRow(
            title: 'Heads-up alerts',
            value: prefs.headsUpAlerts,
            onChanged: (!pushEnabled || prefsLoading)
                ? null
                : (value) async {
                    await ref
                        .read(notificationPreferencesProvider.notifier)
                        .setHeadsUpAlerts(value);
                  },
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 10.h),
        child: Text(
          title,
          style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36.h,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: kPrimaryColor,
          ),
        ],
      ),
    );
  }
}
