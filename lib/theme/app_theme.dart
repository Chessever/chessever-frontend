// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepPurple, // Example seed color
      brightness: Brightness.dark,
    ),
    // Optional: Customize specific components for dark theme
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.grey, // Slightly custom AppBar color for dark
      elevation: 0, // Flat AppBar
    ),
    // Ensure Material 3 is enabled (default in recent Flutter versions)
    useMaterial3: true,
  );

  static final ThemeData lightTheme = ThemeData( // Define a light theme too (good practice)
     brightness: Brightness.light,
     colorScheme: ColorScheme.fromSeed(
       seedColor: Colors.deepPurple, // Use the same seed
       brightness: Brightness.light,
     ),
     appBarTheme: AppBarTheme(
        backgroundColor: Colors.deepPurple, // Custom AppBar for light
        foregroundColor: Colors.white, // Ensure text/icons are visible
        elevation: 4,
     ),
     useMaterial3: true,
  );
}