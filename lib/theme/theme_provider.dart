import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// StateNotifier to manage ThemeMode
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  // Changed default from ThemeMode.system to ThemeMode.dark
  ThemeModeNotifier() : super(ThemeMode.dark);

  void setTheme(ThemeMode mode) => state = mode;

  void toggleTheme() {
    if (state == ThemeMode.dark) {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.dark;
    }
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);
