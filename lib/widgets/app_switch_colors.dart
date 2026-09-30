import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Colours for the house switch (a cyan thumb on a 35% cyan track), for
/// `Switch` / `Switch.adaptive`'s `thumbColor` and `trackColor`.
///
/// Dark returns exactly the historic values. On paper that pairing is a
/// cyan dot on a pale cyan wash, ~1.6:1 between on and off, so light mode
/// draws on as a surface thumb on an accent-text track (6.8:1) and off as a
/// secondary-ink thumb on the recessed track (4.5:1).
WidgetStateProperty<Color?> appSwitchThumbColor(
  BuildContext context, {
  Color? darkOffThumb,
}) {
  final colors = context.colors;
  final light = context.isLightTheme;
  return WidgetStateProperty.resolveWith((states) {
    final on = states.contains(WidgetState.selected);
    if (light) return on ? colors.surface : colors.textSecondary;
    return on ? kPrimaryColor : (darkOffThumb ?? kPrimaryColor);
  });
}

/// Track half of [appSwitchThumbColor].
WidgetStateProperty<Color?> appSwitchTrackColor(BuildContext context) {
  final colors = context.colors;
  final light = context.isLightTheme;
  return WidgetStateProperty.resolveWith((states) {
    final on = states.contains(WidgetState.selected);
    if (light) return on ? colors.accentText : colors.surfaceRecessed;
    return on
        ? kPrimaryColor.withValues(alpha: 0.35)
        : colors.divider.withValues(alpha: 0.5);
  });
}
