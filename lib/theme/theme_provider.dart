import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _themeModeStorageKey = 'app.theme_mode.v1';

/// StateNotifier managing the active [ThemeMode]. The selection is persisted
/// to SharedPreferences so the user's choice survives app restarts. We never
/// throw if storage is unavailable — the app simply falls back to the default.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _restore();
  }

  void setTheme(ThemeMode mode) {
    if (state == mode) return;
    state = mode;
    _persist(mode);
  }

  void toggleTheme() {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setTheme(next);
  }

  Future<void> _restore() async {
    try {
      final prefs = SharedPreferencesService.instance.prefsOrNull;
      if (prefs == null) return;
      final raw = prefs.getString(_themeModeStorageKey);
      final restored = _decode(raw);
      if (restored != null && restored != state) {
        state = restored;
      }
    } catch (e, st) {
      debugPrint('[theme] failed to restore theme mode: $e\n$st');
    }
  }

  Future<void> _persist(ThemeMode mode) async {
    try {
      final prefs = SharedPreferencesService.instance.prefsOrNull;
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

  static ThemeMode? _decode(String? raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);
