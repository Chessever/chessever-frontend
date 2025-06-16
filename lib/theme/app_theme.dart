import 'package:flutter/material.dart';

// Color constants
const Color kPrimaryColor = Color(0xFF0FB4E5); // PRIMARY COLOR
const Color kBackgroundColor = Color(0xFF0C0C0E); // BACKGROUND
const Color kWhiteColor = Color(0xFFFFFFFF); // WHITE
const Color kBlack2Color = Color(0xFF1A1A1C); // BLACK#2
const Color kDarkGreyColor = Color(0xFF333333);
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
