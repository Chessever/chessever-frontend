import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

// Color constants
const Color kPrimaryColor = Color(0xFF0FB4E5); // PRIMARY COLOR
const Color kDarkBlue = Color(0xFF17AAD6);
const Color kBlackColor = Color(0xFF000000); // BACKGROUND
const Color kBackgroundColor = Color(0xFF0C0C0E); // BACKGROUND
const Color kLightYellowColor = Color(0xFFE9EDCC); // BACKGROUND
const Color kWhiteColor = Color(0xFFFFFFFF); // WHITE
const Color kPopUpColor = Color(0xff111111);
const Color kWhiteColor70 = Color(
  0xB3FFFFFF,
); // WHITE with 70% opacity (B3 = 70%)
const Color kDividerColor = Color(0xFF2C2C2E);
const Color kBlack2Color = Color(0xFF1A1A1C); // BLACK#2
const Color kBlack3Color = Color(0xFF252527); // BLACK#3
const Color kLightGreyColor = Color(0xFF666666);
const Color kDarkGreyColor = Color(0xFF262626);
const Color kGrey900 = Color.fromRGBO(33, 33, 33, 1);
const Color kLightBlack = Color(0xFF222222);
const Color kGreenColor = Color(0xFF009C42); // GREEN
const Color kGreenColor2 = Color(0xFF45C86E); // GREEN
const Color kRedColor = Color(0xFFF5453A); // RED
const Color kDarkRedColor = Color.fromRGBO(255, 100, 103, 0.7); // DARKRED

// Move statistics bar segment colors (Lichess-style: white / grey / black)
const Color kMoveStatWhiteColor = Color(0xFFF0F0F0); // White wins segment
const Color kMoveStatDrawColor = Color(
  0xFF40404E,
); // Draw segment (dark slate grey)
const Color kMoveStatBlackColor = Color(
  0xFF0A0A0A,
); // Black wins segment (near-black)
const Color kChessBlackMoveColor = Color(
  0xFFFF8A65,
); // Warm coral-orange for black moves
const Color kLastMoveHighlightColor = Color(
  0xFFADB9CF,
); // Opaque blue-grey: renders distinct light/dark square hues
const Color kLastMoveHighlightLightSquare = Color(
  0xFFADB9CF,
); // Last-move highlight on light squares
const Color kLastMoveHighlightDarkSquare = Color(
  0xFF9DAAC2,
); // Last-move highlight on dark squares
const Color kActiveCalendarColor = Color(0xff68D3FF);
const Color kpinColor = Color(0xFFBD3D44);
const Color kBoardColorDefault = Color(0xFF6B939F); // Default
const Color kBoardColorBrown = Color(0xFF855E39); // Brown
const Color kBoardColorGrey = Color(0xFF9E9E9E); // Grey
const Color kBoardColorGreen = Color(0xFFB1D9B0); // Green
const Color kgradientStartColors = Color(0xFF170116); // Green
const Color kgradientEndColors = Color(0xFF005B57); // Green
const Color kLightPink = Color(0xFFF39FD5);
const Color kborderLeftColors = Color(0xFF253135);
// Add these to your app_theme.dart
const Color kBoardDarkGreen = Color(0xFFB1D9B0);
const Color kBoardLightGreen = Colors.white; // #FFFFFF
const Color kBoardLightGrey = Color(0xFFD9D9D9);
const Color kBoardLightBrown = Color(0xFFC29D62);
const Color kBoardLightDefault = Color(0xFFD1E9E9);
/// Broadcast Blue set used by the light-theme board mock. Chrome around the
/// board always follows [AppColors]; these squares apply only when the user
/// is on the default board theme and the app is in light mode.
const Color kBoardLightThemeLightSquare = Color(0xFFDEE3E6);
const Color kBoardLightThemeDarkSquare = Color(0xFF8CA2AD);

const Color kInactiveTabColor = Color(
  0x66FFFFFF,
); // White with 40% opacity (66 = 40%)

// Secondary/hint text colors with proper contrast on dark backgrounds
const Color kSecondaryTextColor = Color(
  0xFF8E8E93,
); // iOS system gray - good contrast on dark
const Color kTertiaryTextColor = Color(
  0xFF636366,
); // Slightly dimmer but still readable
const Color kPlaceholderColor = Color(
  0xFF48484A,
); // For disabled/placeholder states
const Color kSubtleIconColor = Color(0xFF8E8E93); // For secondary icons
const LinearGradient kAppLinearGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFFFFFFFF), // #FFF
    Color(0xFF999999), // #999
  ],
  stops: [0.0, 1.0],
  transform: GradientRotation(75 * 3.1415927 / 180),
);

// Dim/scrim painted by [BackDropFilterWidget] behind dialogs. A black radial
// vignette (lighter at the focused center, darker at the edges) carries the
// "blacked out" dim now that the backdrop blur composites with the default
// srcOver blend instead of luminosity. srcOver blurs+dims EVERYTHING uniformly
// — including saturated country flags, which previously kept their full colour
// because luminosity blending preserves the destination's chroma. Tune the two
// alphas to make the background darker/lighter.
RadialGradient radialOverlayGradient = RadialGradient(
  colors: [kBlackColor.withValues(alpha: 0.40), kBlackColor.withValues(alpha: 0.58)],
);

// Profile initials gradient
const LinearGradient kProfileInitialsGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF0FB4E5), // 0FB4E5 (0%)
    Color(0xFF08647F), // 08647F (100%)
  ],
  stops: [0.0, 1.0],
);

class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimaryColor,
      brightness: Brightness.dark,
      surface: kBlack2Color,
      onSurface: kWhiteColor,
    ).copyWith(
      primary: kPrimaryColor,
      onPrimary: kWhiteColor,
      surface: kBlack2Color,
      onSurface: kWhiteColor,
      surfaceContainerHighest: kBlack3Color,
      outline: kDividerColor,
      error: kRedColor,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBackgroundColor,
      foregroundColor: kWhiteColor,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),
    scaffoldBackgroundColor: kBackgroundColor,
    canvasColor: kBackgroundColor,
    dividerColor: kDividerColor,
    iconTheme: const IconThemeData(color: kWhiteColor),
    drawerTheme: const DrawerThemeData(
      backgroundColor: kBackgroundColor,
      scrimColor: Color(0x8C000000),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: kPopUpColor,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kBlack2Color,
      modalBarrierColor: Color(0x99000000),
      surfaceTintColor: Colors.transparent,
    ),
    extensions: const [_darkAppColors],
    useMaterial3: true,
  );

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimaryColor,
      brightness: Brightness.light,
    ).copyWith(
      primary: kPrimaryColor,
      onPrimary: kWhiteColor,
      surface: const Color(0xFFF4FAF9),
      onSurface: const Color(0xFF0E1A1C),
      surfaceContainerHighest: const Color(0xFFC5D6D5),
      outline: const Color(0xFFB7C9C8),
      error: kRedColor,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFE2ECEC),
      foregroundColor: Color(0xFF0E1A1C),
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),
    scaffoldBackgroundColor: const Color(0xFFE2ECEC),
    canvasColor: const Color(0xFFE2ECEC),
    dividerColor: const Color(0xFFB7C9C8),
    iconTheme: const IconThemeData(color: Color(0xFF0E1A1C)),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Color(0xFFE2ECEC),
      scrimColor: Color(0x660E1A1C),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFFF4FAF9),
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFFF4FAF9),
      modalBarrierColor: Color(0x660E1A1C),
      surfaceTintColor: Colors.transparent,
    ),
    extensions: const [_lightAppColors],
    useMaterial3: true,
  );

  /// Status / nav bar overlay that flips with the resolved brightness.
  static SystemUiOverlayStyle overlayFor(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness:
          isLight ? Brightness.dark : Brightness.light,
      systemNavigationBarContrastEnforced: false,
    );
  }
}

// Forward-declared via app_colors.dart import at the call sites; we redeclare
// the references here as constants to keep ThemeData.extensions list `const`.
const _darkAppColors = AppColors.dark;
const _lightAppColors = AppColors.light;
