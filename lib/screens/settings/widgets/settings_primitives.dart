import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.textLgMedium.copyWith(
        color: context.colors.textPrimary,
        fontSize: 14.f,
      ),
    );
  }
}

class SettingCard extends StatelessWidget {
  const SettingCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18.br),
        border: Border.all(
          color: context.colors.divider.withValues(alpha: 0.4),
        ),
        boxShadow: context.isLightTheme
            ? [
                BoxShadow(
                  color: context.colors.shadow,
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// Thumb for every settings switch (board, engine). Dark mode keeps the
/// historic cyan thumb (accentText is kPrimaryColor there). On paper a cyan
/// thumb over a faint cyan track reads ~2.3:1 / ~1.35:1, so light mode puts a
/// white thumb on a solid accent-text track instead. The OFF thumb is always
/// grey, so ON and OFF never share a colour.
WidgetStateProperty<Color?> settingsSwitchThumb(BuildContext context) {
  final colors = context.colors;
  final isLight = context.isLightTheme;
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.selected)) {
      return isLight ? colors.surface : colors.accentText;
    }
    // Full-strength grey on paper: at 0.6 it fell to ~2.4:1 on the track.
    return isLight
        ? colors.textSecondary
        : colors.textSecondary.withValues(alpha: 0.6);
  });
}

/// Track for every settings switch (board, engine). Light ON is the solid
/// accent-text teal (~7:1 on the card); dark keeps the historic 35% cyan.
WidgetStateProperty<Color?> settingsSwitchTrack(BuildContext context) {
  final colors = context.colors;
  final isLight = context.isLightTheme;
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.selected)) {
      return isLight
          ? colors.accentText
          : colors.accentText.withValues(alpha: 0.35);
    }
    return colors.divider.withValues(alpha: 0.5);
  });
}

/// A settings row that opens a picker: its title (and an optional caption
/// under it), the current value, and a chevron. Shared by Settings ›
/// Customization's Start screen and Collection stories.
class SettingsPickerRow extends StatelessWidget {
  const SettingsPickerRow({
    super.key,
    required this.title,
    required this.value,
    required this.onTap,
    this.caption,
  });

  final String title;
  final String value;
  final VoidCallback onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Text(
                  value,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                SizedBox(width: 4.w),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20.ic,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
            if (caption != null) ...[
              SizedBox(height: 4.h),
              Text(
                caption!,
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
