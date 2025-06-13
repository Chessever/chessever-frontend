import 'package:flutter/material.dart';

// Color constants
const Color kPrimaryColor = Color(0xFF673AB7);
const Color kDarkAppBarColor = Color(0xFF232136);
const Color kDarkScaffoldBackground = Color(0xFF181825);
const Color kLightScaffoldBackground = Color(0xFFF5F5FA);

class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimaryColor,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kDarkAppBarColor,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    scaffoldBackgroundColor: kDarkScaffoldBackground,
    useMaterial3: true,
  );

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimaryColor,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kPrimaryColor,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
    scaffoldBackgroundColor: kLightScaffoldBackground,
    useMaterial3: true,
  );
}
