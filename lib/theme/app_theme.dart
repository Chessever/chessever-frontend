import 'package:flutter/material.dart';

// Color constants
const Color kPrimaryColor = Color(0xFF0FB4E5); // PRIMARY COLOR
const Color kLightBlue = Color(0xFF86FFFD); // PRIMARY COLOR
const Color kBlackColor = Color(0xFF000000); // BACKGROUND
const Color kBackgroundColor = Color(0xFF0C0C0E); // BACKGROUND
const Color kWhiteColor = Color(0xFFFFFFFF); // WHITE
const Color kPopUpColor = Color(0xff111111);
const Color kWhiteColor70 = Color(
  0xB3FFFFFF,
); // WHITE with 70% opacity (B3 = 70%)
const Color kDividerColor = Color(0xFF2C2C2E);
const Color kBlack2Color = Color(0xFF1A1A1C); // BLACK#2
const Color kDarkGreyColor = Color(0xFF333333);
const Color kLightBlack = Color(0xFF222222);
const Color kGreenColor = Color(0xFF009C42); // GREEN
const Color kGreenColor2 = Color(0xFF45C86E); // GREEN
const Color kRedColor = Color(0xFFF5453A); // RED
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

const Color kInactiveTabColor = Color(
  0x669D9D9D,
); // #9D9D9D with 40% opacity (66 = 40%)
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

RadialGradient radialOverlayGradient = RadialGradient(
  colors: [kWhiteColor.withAlpha(20), kLightBlack.withAlpha(20)],
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
      background: kBackgroundColor,
      primary: kPrimaryColor,
      onPrimary: kWhiteColor,
      surface: kBlack2Color,
      onSurface: kWhiteColor,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBackgroundColor,
      foregroundColor: kWhiteColor,
      elevation: 0,
    ),
    scaffoldBackgroundColor: kBackgroundColor,
    useMaterial3: true,
  );

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimaryColor,
      brightness: Brightness.light,
      background: kBackgroundColor,
      primary: kPrimaryColor,
      onPrimary: kWhiteColor,
      surface: kWhiteColor,
      onSurface: kBlack2Color,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kPrimaryColor,
      foregroundColor: kWhiteColor,
      elevation: 4,
    ),
    scaffoldBackgroundColor: kBackgroundColor,
    useMaterial3: true,
  );
}
