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
    // Tertiary / placeholder / danger are deepened from the raw hand-off
    // (#6B7C7E / #8A9A9C / kRedColor) so small text clears WCAG AA on paper.
    expect(light.textTertiary, const Color(0xFF58696B));
    expect(light.placeholder, const Color(0xFF6E7F81));
    expect(light.brand, kPrimaryColor);
    expect(light.brandMuted, const Color(0xFF17AAD6));
    expect(light.danger, const Color(0xFFC53128));
    expect(light.accentText, const Color(0xFF005F7D));
    expect(light.surfaceInverse, const Color(0xFF0E1A1C));
    expect(light.textInverse, const Color(0xFFE2ECEC));
    expect(light.titleAccent, const Color(0xFF4F5334));
    expect(light.inkOnAccent, const Color(0xFF0A0A0A));
    expect(light.scrim, const Color(0x660E1A1C));
    expect(light.evalWhite, const Color(0xFFE8EAED));
    // Deepened from the hand-off rail (#B7C6C7, 1.46:1) so the split reads.
    expect(light.evalBlack, const Color(0xFF5E7174));
  });

  test('light eval bar shares separate at 3:1 or more', () {
    const light = AppColors.light;
    for (final paper in [light.evalWhite, light.background, light.surface]) {
      expect(wcagContrast(light.evalBlack, paper), greaterThanOrEqualTo(3));
    }
  });

  test('AppColors.dark keeps the historic chrome tokens', () {
    const dark = AppColors.dark;
    expect(dark.background, kBackgroundColor);
    expect(dark.surface, kBlack2Color);
    expect(dark.surfaceElevated, kPopUpColor);
    expect(dark.textPrimary, kWhiteColor);
    expect(dark.titleAccent, kLightYellowColor);
    expect(dark.inkOnAccent, kBlack3Color);
    expect(dark.evalWhite, kWhiteColor);
    expect(dark.evalBlack, kPopUpColor);
    expect(dark.accentText, kPrimaryColor);
    expect(dark.danger, kRedColor);
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
