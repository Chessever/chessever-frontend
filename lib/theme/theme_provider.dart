import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _themeModeStorageKey = 'app.theme_mode.v1';

/// StateNotifier managing the active [ThemeMode]. Light theme is temporarily
/// disabled, so this always stays on [ThemeMode.dark] and overwrites any
/// previously persisted light/system choice.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _restore();
  }

  void setTheme(ThemeMode mode) {
    // Light theme is temporarily disabled.
    if (mode != ThemeMode.dark) return;
    if (state == mode) return;
    state = mode;
    _persist(mode);
  }

  void toggleTheme() {
    setTheme(ThemeMode.dark);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      if (prefs == null) return;
      // Do not restore light/system — pin the stored value back to dark.
      await prefs.setString(_themeModeStorageKey, _encode(ThemeMode.dark));
      if (state != ThemeMode.dark) {
        state = ThemeMode.dark;
      }
    } catch (e, st) {
      debugPrint('[theme] failed to restore theme mode: $e\n$st');
    }
  }

  Future<void> _persist(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      if (prefs == null) return;
      await prefs.setString(_themeModeStorageKey, _encode(mode));
    } catch (e, st) {
      debugPrint('[theme] failed to persist theme mode: $e\n$st');
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);
