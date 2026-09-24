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
    required this.evalWhite,
    required this.evalBlack,
    required this.accentText,
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

  /// Eval-bar white share. Dark keeps historic `textPrimary` white; light uses
  /// broadcast `--eval-white` so the fill stays paper, not a flipped ink block.
  final Color evalWhite;

  /// Eval-bar black share / rail. Dark keeps historic `popup` near-black; light
  /// uses a slate teal (not a near-black slab) deep enough that the split
  /// against [evalWhite] clears 3:1.
  final Color evalBlack;

  /// Brand cyan for TEXT, links and selected-state icons. Dark keeps the
  /// historic [kPrimaryColor]; light deepens it to a teal-blue so it clears
  /// WCAG AA (≥4.5:1) on paper, where raw brand cyan only reaches ~2:1.
  /// Fills, rings and indicators keep using [brand].
  final Color accentText;

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
    evalWhite: kWhiteColor,
    evalBlack: kPopUpColor,
    accentText: kPrimaryColor,
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
    // Tertiary / placeholder deepened from the broadcast values (#6B7C7E /
    // #8A9A9C read 3.6:1 / 2.4:1 on the mint background) so small metadata
    // clears AA and hints clear 3:1.
    textTertiary: Color(0xFF58696B),
    textInverse: Color(0xFFE2ECEC),
    placeholder: Color(0xFF6E7F81),
    iconPrimary: Color(0xFF0E1A1C),
    iconSecondary: Color(0xFF58696B),
    // Signal colours deepened for paper: kGreenColor / kRedColor sit at
    // ~3:1 on the mint background, too faint for text-sized labels.
    success: Color(0xFF007A33),
    successStrong: Color(0xFF006B2D),
    danger: Color(0xFFC53128),
    dangerMuted: Color(0xFFA9443D),
    tabInactive: Color(0xB30E1A1C),
    shadow: Color(0x1F0E1A1C),
    scrim: Color(0x660E1A1C),
    skeleton: Color(0xFFC5D6D5),
    // Deep teal (accent-text family) so the white initials drawn on it
    // clear AA (4.9:1 at the lightest stop); brand cyan held them at ~2.4:1.
    profileGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF087A9C), Color(0xFF005F7D)],
      stops: [0.0, 1.0],
    ),
    titleAccent: Color(0xFF4F5334),
    inkOnAccent: Color(0xFF0A0A0A),
    evalWhite: Color(0xFFE8EAED),
    // Deepened from the broadcast `--eval-rail` (#B7C6C7): that sat at
    // 1.46:1 against evalWhite, so nobody could see the split. This slate
    // teal parts from evalWhite and the mint page at 4.26:1. As in dark, one
    // share melts into the page and the other one carries the bar.
    evalBlack: Color(0xFF5E7174),
    accentText: Color(0xFF005F7D),
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
    Color? evalWhite,
    Color? evalBlack,
    Color? accentText,
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
      evalWhite: evalWhite ?? this.evalWhite,
      evalBlack: evalBlack ?? this.evalBlack,
      accentText: accentText ?? this.accentText,
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
      evalWhite: Color.lerp(evalWhite, other.evalWhite, t)!,
      evalBlack: Color.lerp(evalBlack, other.evalBlack, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
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

  /// Primary ink at [alpha], for TEXT. Dark mode returns exactly
  /// `colors.textPrimary.withValues(alpha: alpha)`, so nothing moves there.
  /// On paper a faint ink falls under AA long before it does on black, so
  /// light mode lifts low alphas into a 0.62–0.74 band: every step still
  /// reads lighter than the one above it, and none drops below ~4.5:1 on
  /// the background or surface tokens.
  Color textInk(double alpha) {
    final ink = colors.textPrimary;
    if (!isLightTheme || alpha >= 0.74) return ink.withValues(alpha: alpha);
    return ink.withValues(alpha: 0.62 + alpha.clamp(0.0, 0.74) * 0.16);
  }

  /// A saturated hue drawn as TEXT or ICON ink (a level colour, an ECO
  /// letter, a gold glyph). Dark mode returns [accent] untouched. On paper
  /// most of these sit at 1.2–3:1, so light mode walks the hue toward
  /// `textPrimary` in 5% steps and stops at the first step that clears
  /// [min] against [on] (default: the background token, the darkest paper
  /// most text sits on). The hue survives; only its value drops.
  ///
  /// Keep the raw [accent] for tints, borders and fills.
  Color accentInk(Color accent, {Color? on, double min = 4.5}) {
    if (!isLightTheme) return accent;
    return legibleAccentInk(
      accent,
      ink: colors.textPrimary,
      on: on ?? colors.background,
      min: min,
    );
  }
}

/// WCAG 2.x contrast ratio of [foreground] over [background]. A translucent
/// foreground is composited over the background first, as it renders.
double wcagContrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background);
  final l1 = fg.computeLuminance();
  final l2 = background.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// Theme-free core of [AppColorsContext.accentInk]: the first 5% step from
/// [accent] toward [ink] that reads at [min] on [on], or [ink] itself.
Color legibleAccentInk(
  Color accent, {
  required Color ink,
  required Color on,
  double min = 4.5,
}) {
  for (var step = 0; step <= 20; step++) {
    final candidate = Color.lerp(accent, ink, step / 20)!;
    if (wcagContrast(candidate, on) >= min) return candidate;
  }
  return ink;
}
