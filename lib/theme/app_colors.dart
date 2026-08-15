import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Semantic color tokens used across the app. The dark variant maps 1:1 to the
/// historical `k*Color` constants in `app_theme.dart`; the light variant is the
/// broadcast mint/teal palette from `ChessEver Light Theme.dc.html` §4a.
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
    required this.titleAccent,
    required this.inkOnAccent,
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

  /// Chess title prefix (GM, IM, …). Dark keeps the historic gold; light uses
  /// broadcast `--title` so the ink stays readable on paper.
  final Color titleAccent;

  /// Ink that sits on a saturated brand fill (BEST VALUE, similar chips).
  /// Dark keeps a dark recessed tone; light pins to broadcast `--ink-on-accent`.
  final Color inkOnAccent;

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
    titleAccent: kLightYellowColor,
    inkOnAccent: kBlack3Color,
  );

  /// Broadcast-ported mint/teal light palette. Values come from
  /// `ChessEver Light Theme.dc.html` §4a — do not drift back to iOS greys.
  static const AppColors light = AppColors(
    brand: kPrimaryColor,
    brandMuted: Color(0xFF17AAD6),
    background: Color(0xFFE2ECEC),
    surface: Color(0xFFF4FAF9),
    surfaceElevated: Color(0xFFEEF6F5),
    surfaceRecessed: Color(0xFFC5D6D5),
    surfaceInverse: Color(0xFF0E1A1C),
    popup: Color(0xFFF4FAF9),
    divider: Color(0xFFB7C9C8),
    dividerStrong: Color(0xFFB7C9C8),
    textPrimary: Color(0xFF0E1A1C),
    textPrimaryMuted: Color(0xB30E1A1C),
    textSecondary: Color(0xFF4D5E61),
    textTertiary: Color(0xFF6B7C7E),
    textInverse: Color(0xFFE2ECEC),
    placeholder: Color(0xFF8A9A9C),
    iconPrimary: Color(0xFF0E1A1C),
    iconSecondary: Color(0xFF6B7C7E),
    success: kGreenColor,
    successStrong: Color(0xFF007A33),
    danger: kRedColor,
    dangerMuted: kDarkRedColor,
    tabInactive: Color(0xB30E1A1C),
    shadow: Color(0x1F0E1A1C),
    scrim: Color(0x660E1A1C),
    skeleton: Color(0xFFC5D6D5),
    profileGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0FB4E5), Color(0xFF0894C2)],
      stops: [0.0, 1.0],
    ),
    titleAccent: Color(0xFF4F5334),
    inkOnAccent: Color(0xFF0A0A0A),
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
    Color? titleAccent,
    Color? inkOnAccent,
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
      titleAccent: titleAccent ?? this.titleAccent,
      inkOnAccent: inkOnAccent ?? this.inkOnAccent,
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
      titleAccent: Color.lerp(titleAccent, other.titleAccent, t)!,
      inkOnAccent: Color.lerp(inkOnAccent, other.inkOnAccent, t)!,
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
