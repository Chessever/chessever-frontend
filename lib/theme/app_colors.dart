import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Semantic color tokens used across the app. The dark variant maps 1:1 to the
/// historical `k*Color` constants in `app_theme.dart`; the light variant is a
/// freshly-designed iOS-leaning palette that preserves brand identity while
/// staying comfortable on a bright background.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brand,
    required this.brandMuted,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceRecessed,
    required this.surfaceInverse,
    required this.popup,
    required this.divider,
    required this.dividerStrong,
    required this.textPrimary,
    required this.textPrimaryMuted,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.placeholder,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.success,
    required this.successStrong,
    required this.danger,
    required this.dangerMuted,
    required this.tabInactive,
    required this.shadow,
    required this.scrim,
    required this.skeleton,
    required this.profileGradient,
  });

  final Color brand;
  final Color brandMuted;
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceRecessed;
  final Color surfaceInverse;
  final Color popup;
  final Color divider;
  final Color dividerStrong;
  final Color textPrimary;
  final Color textPrimaryMuted;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInverse;
  final Color placeholder;
  final Color iconPrimary;
  final Color iconSecondary;
  final Color success;
  final Color successStrong;
  final Color danger;
  final Color dangerMuted;
  final Color tabInactive;
  final Color shadow;
  final Color scrim;
  final Color skeleton;
  final LinearGradient profileGradient;

  static const AppColors dark = AppColors(
    brand: kPrimaryColor,
    brandMuted: Color(0xFF17AAD6),
    background: kBackgroundColor,
    surface: kBlack2Color,
    surfaceElevated: kPopUpColor,
    surfaceRecessed: kBlack3Color,
    surfaceInverse: kWhiteColor,
    popup: kPopUpColor,
    divider: kDividerColor,
    dividerStrong: Color(0xFF3A3A3C),
    textPrimary: kWhiteColor,
    textPrimaryMuted: kWhiteColor70,
    textSecondary: kSecondaryTextColor,
    textTertiary: kTertiaryTextColor,
    textInverse: kBlackColor,
    placeholder: kPlaceholderColor,
    iconPrimary: kWhiteColor,
    iconSecondary: kSubtleIconColor,
    success: kGreenColor2,
    successStrong: kGreenColor,
    danger: kRedColor,
    dangerMuted: kDarkRedColor,
    tabInactive: kInactiveTabColor,
    shadow: Color(0xCC000000),
    scrim: Color(0xB3000000),
    skeleton: Color(0xFF2A2A2C),
    profileGradient: kProfileInitialsGradient,
  );

  /// iOS-leaning premium light palette. Off-white scaffold so the eye relaxes;
  /// pure white cards for crisp contrast; brand cyan stays the same so the
  /// product still feels like ChessEver.
  static const AppColors light = AppColors(
    brand: kPrimaryColor,
    brandMuted: Color(0xFF0894C2),
    background: Color(0xFFF2F2F7), // iOS systemGroupedBackground
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceRecessed: Color(0xFFEDEDF2),
    surfaceInverse: Color(0xFF1C1C1E),
    popup: Color(0xFFFFFFFF),
    divider: Color(0xFFE5E5EA),
    dividerStrong: Color(0xFFD1D1D6),
    textPrimary: Color(0xFF1C1C1E), // near-black, never pure black
    textPrimaryMuted: Color(0xB31C1C1E), // 70% opacity equivalent
    textSecondary: Color(0xFF6D6D72), // iOS secondaryLabel
    textTertiary: Color(0xFF8E8E93), // iOS tertiaryLabel
    textInverse: Color(0xFFFFFFFF),
    placeholder: Color(0xFFC7C7CC),
    iconPrimary: Color(0xFF1C1C1E),
    iconSecondary: Color(0xFF8E8E93),
    success: Color(0xFF34C759), // iOS systemGreen
    successStrong: Color(0xFF248A3D),
    danger: Color(0xFFFF3B30), // iOS systemRed
    dangerMuted: Color(0xFFFF6B6B),
    tabInactive: Color(0x661C1C1E),
    shadow: Color(0x1F000000),
    scrim: Color(0x66000000),
    skeleton: Color(0xFFE5E5EA),
    profileGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0FB4E5), Color(0xFF0894C2)],
      stops: [0.0, 1.0],
    ),
  );

  @override
  AppColors copyWith({
    Color? brand,
    Color? brandMuted,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceRecessed,
    Color? surfaceInverse,
    Color? popup,
    Color? divider,
    Color? dividerStrong,
    Color? textPrimary,
    Color? textPrimaryMuted,
    Color? textSecondary,
    Color? textTertiary,
    Color? textInverse,
    Color? placeholder,
    Color? iconPrimary,
    Color? iconSecondary,
    Color? success,
    Color? successStrong,
    Color? danger,
    Color? dangerMuted,
    Color? tabInactive,
    Color? shadow,
    Color? scrim,
    Color? skeleton,
    LinearGradient? profileGradient,
  }) {
    return AppColors(
      brand: brand ?? this.brand,
      brandMuted: brandMuted ?? this.brandMuted,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceRecessed: surfaceRecessed ?? this.surfaceRecessed,
      surfaceInverse: surfaceInverse ?? this.surfaceInverse,
      popup: popup ?? this.popup,
      divider: divider ?? this.divider,
      dividerStrong: dividerStrong ?? this.dividerStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textPrimaryMuted: textPrimaryMuted ?? this.textPrimaryMuted,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textInverse: textInverse ?? this.textInverse,
      placeholder: placeholder ?? this.placeholder,
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconSecondary: iconSecondary ?? this.iconSecondary,
      success: success ?? this.success,
      successStrong: successStrong ?? this.successStrong,
      danger: danger ?? this.danger,
      dangerMuted: dangerMuted ?? this.dangerMuted,
      tabInactive: tabInactive ?? this.tabInactive,
      shadow: shadow ?? this.shadow,
      scrim: scrim ?? this.scrim,
      skeleton: skeleton ?? this.skeleton,
      profileGradient: profileGradient ?? this.profileGradient,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      brand: Color.lerp(brand, other.brand, t)!,
      brandMuted: Color.lerp(brandMuted, other.brandMuted, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceRecessed: Color.lerp(surfaceRecessed, other.surfaceRecessed, t)!,
      surfaceInverse: Color.lerp(surfaceInverse, other.surfaceInverse, t)!,
      popup: Color.lerp(popup, other.popup, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      dividerStrong: Color.lerp(dividerStrong, other.dividerStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textPrimaryMuted:
          Color.lerp(textPrimaryMuted, other.textPrimaryMuted, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      iconPrimary: Color.lerp(iconPrimary, other.iconPrimary, t)!,
      iconSecondary: Color.lerp(iconSecondary, other.iconSecondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      successStrong: Color.lerp(successStrong, other.successStrong, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerMuted: Color.lerp(dangerMuted, other.dangerMuted, t)!,
      tabInactive: Color.lerp(tabInactive, other.tabInactive, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      skeleton: Color.lerp(skeleton, other.skeleton, t)!,
      profileGradient: t < 0.5 ? profileGradient : other.profileGradient,
    );
  }
}

extension AppColorsContext on BuildContext {
  /// Resolve the active [AppColors] from the nearest [Theme]. Falls back to
  /// [AppColors.dark] if (somehow) the extension is missing — this is the
  /// historical default and keeps screens rendering.
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.dark;

  /// Convenience: true when the current theme is light.
  bool get isLightTheme => Theme.of(this).brightness == Brightness.light;
}
