import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _themeModeStorageKey = 'app.theme_mode.v1';

/// StateNotifier managing the active [ThemeMode]. The selection is persisted
/// to SharedPreferences so the user's choice survives app restarts. We never
/// throw if storage is unavailable: the app simply falls back to dark.
///
/// The saved choice is read synchronously when the prefs cache is already
/// warm (startup initialises it before the app builds), so a Light user's
/// first frame is already in their theme instead of a dark frame that fades
/// across. Only a cold cache falls back to the async restore.
///
/// Auto (follow the system) is not offered for now: a stored `system` choice
/// reads as the default, dark, so nobody is left in a mode the picker cannot
/// show.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(_cachedMode() ?? ThemeMode.dark) {
    if (SharedPreferencesService.instance.prefsOrNull == null) _restore();
  }

  /// Set once the user picks a theme, so a late async restore never
  /// overwrites a choice made while it was in flight.
  bool _userChose = false;

  static ThemeMode? _cachedMode() {
    try {
      return _decode(
        SharedPreferencesService.instance.prefsOrNull?.getString(
          _themeModeStorageKey,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void setTheme(ThemeMode mode) {
    _userChose = true;
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
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      if (prefs == null || _userChose || !mounted) return;
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

  static ThemeMode? _decode(String? raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return null;
    }
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);
