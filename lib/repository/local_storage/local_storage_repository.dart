import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;

/// Singleton class to hold the pre-initialized SharedPreferences instance.
/// This prevents multiple calls to SharedPreferences.getInstance() which can
/// cause hangs on Android when the preferences file is corrupted or being
/// accessed by multiple isolates.
///
/// IMPORTANT: All methods have timeout protection to prevent app hangs.
/// If SharedPreferences fails/times out, operations fail gracefully.
class SharedPreferencesService {
  SharedPreferencesService._();
  static final SharedPreferencesService _instance =
      SharedPreferencesService._();
  static SharedPreferencesService get instance => _instance;

  SharedPreferences? _prefs;
  Future<SharedPreferences?>? _initFuture;
  bool _initFailed = false;

  /// Timeout for SharedPreferences operations
  static const Duration _timeout = Duration(seconds: 3);

  /// Returns the cached SharedPreferences instance, or null if unavailable.
  SharedPreferences? get prefsOrNull => _prefs;

  /// Returns the cached SharedPreferences instance.
  /// Throws if not initialized - call initialize() first in main().
  SharedPreferences get prefs {
    if (_prefs == null) {
      throw StateError(
        'SharedPreferencesService not initialized. '
        'Call SharedPreferencesService.instance.initialize() in main() first.',
      );
    }
    return _prefs!;
  }

  /// Initialize SharedPreferences once at app startup.
  /// Has timeout protection - returns null if initialization fails/times out.
  Future<SharedPreferences?> initialize() async {
    if (_prefs != null) return _prefs!;
    if (_initFailed) return null;

    _initFuture ??= _initWithTimeout();
    return _initFuture;
  }

  Future<SharedPreferences?> _initWithTimeout() async {
    try {
      _prefs = await SharedPreferences.getInstance().timeout(_timeout);
      return _prefs;
    } catch (e) {
      _initFailed = true;
      if (kDebugMode) {
        debugPrint('⚠️ SharedPreferences init failed/timed out: $e');
      }
      return null;
    }
  }

  /// Ensure preferences are initialized, even if main() didn't await it.
  /// Has timeout protection - returns null if unavailable.
  Future<SharedPreferences?> ensureInitialized() async {
    if (_prefs != null) return _prefs!;
    if (_initFailed) return null;
    return initialize();
  }

  /// Check if the service has been initialized successfully.
  bool get isInitialized => _prefs != null;

  /// Check if initialization was attempted but failed.
  bool get initializationFailed => _initFailed;
}

final sharedPreferencesRepository = AutoDisposeProvider<AppSharedPreferences>((
  ref,
) {
  return AppSharedPreferences();
});

/// SharedPreferences wrapper with timeout protection.
/// All methods fail gracefully if SharedPreferences is unavailable.
///
/// NOTE: This class is ONLY for legacy code during migration.
/// New code should use SQLite via AppDatabase instead.
class AppSharedPreferences {
  AppSharedPreferences();

  Future<SharedPreferences?> _getPrefs() async =>
      SharedPreferencesService.instance.ensureInitialized();

  Future<void> setInt(String key, int value) async {
    final prefs = await _getPrefs();
    if (prefs == null) return;
    await prefs.setInt(key, value);
  }

  Future<int?> getInt(String key) async {
    final prefs = await _getPrefs();
    if (prefs == null) return null;
    return prefs.getInt(key);
  }

  Future<void> setBool(String key, bool value) async {
    final prefs = await _getPrefs();
    if (prefs == null) return;
    await prefs.setBool(key, value);
  }

  Future<bool?> getBool(String key) async {
    final prefs = await _getPrefs();
    if (prefs == null) return null;
    return prefs.getBool(key);
  }

  Future<void> setString(String key, String value) async {
    final prefs = await _getPrefs();
    if (prefs == null) return;
    await prefs.setString(key, value);
  }

  Future<String?> getString(String key) async {
    final prefs = await _getPrefs();
    if (prefs == null) return null;
    return prefs.getString(key);
  }

  Future<void> setStringList(String key, List<String> value) async {
    final prefs = await _getPrefs();
    if (prefs == null) return;
    await prefs.setStringList(key, value);
  }

  Future<List<String>> getStringList(String key) async {
    final prefs = await _getPrefs();
    if (prefs == null) return [];
    return prefs.getStringList(key) ?? [];
  }

  Future<void> removeData(String key) async {
    final prefs = await _getPrefs();
    if (prefs == null) return;
    await prefs.remove(key);
  }
}
