import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
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
        border: Border.all(color: context.colors.divider.withValues(alpha: 0.4)),
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
