import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppColors.light matches the broadcast hand-off tokens', () {
    const light = AppColors.light;
    expect(light.background, const Color(0xFFE2ECEC));
    expect(light.surface, const Color(0xFFF4FAF9));
    expect(light.surfaceElevated, const Color(0xFFEEF6F5));
    expect(light.surfaceRecessed, const Color(0xFFC5D6D5));
    expect(light.popup, const Color(0xFFF4FAF9));
    expect(light.divider, const Color(0xFFB7C9C8));
    expect(light.dividerStrong, const Color(0xFFB7C9C8));
    expect(light.textPrimary, const Color(0xFF0E1A1C));
    expect(light.textPrimaryMuted, const Color(0xB30E1A1C));
    expect(light.textSecondary, const Color(0xFF4D5E61));
    expect(light.textTertiary, const Color(0xFF6B7C7E));
    expect(light.placeholder, const Color(0xFF8A9A9C));
    expect(light.brand, kPrimaryColor);
    expect(light.brandMuted, const Color(0xFF17AAD6));
    expect(light.danger, kRedColor);
    expect(light.surfaceInverse, const Color(0xFF0E1A1C));
    expect(light.textInverse, const Color(0xFFE2ECEC));
    expect(light.titleAccent, const Color(0xFF4F5334));
    expect(light.inkOnAccent, const Color(0xFF0A0A0A));
    expect(light.scrim, const Color(0x660E1A1C));
  });

  test('AppColors.dark keeps the historic chrome tokens', () {
    const dark = AppColors.dark;
    expect(dark.background, kBackgroundColor);
    expect(dark.surface, kBlack2Color);
    expect(dark.surfaceElevated, kPopUpColor);
    expect(dark.textPrimary, kWhiteColor);
    expect(dark.titleAccent, kLightYellowColor);
    expect(dark.inkOnAccent, kBlack3Color);
  });

  test('light ThemeData wires the light extension and mint scaffold', () {
    final theme = AppTheme.lightTheme;
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFE2ECEC));
    expect(theme.extension<AppColors>()?.background, AppColors.light.background);
    expect(theme.extension<AppColors>()?.textPrimary, AppColors.light.textPrimary);
  });

  test('overlayFor flips status-bar icon brightness', () {
    expect(
      AppTheme.overlayFor(Brightness.light).statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      AppTheme.overlayFor(Brightness.dark).statusBarIconBrightness,
      Brightness.light,
    );
  });
}
