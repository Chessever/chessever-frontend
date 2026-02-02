import 'dart:async';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Safe LocalStorage for Supabase that avoids startup hangs on Android
/// when SharedPreferences is corrupted or stuck.
///
/// Falls back to in-memory storage if SharedPreferences doesn't initialize
/// within [initTimeout]. This lets the app boot and recover instead of
/// remaining stuck on splash.
class SafeSupabaseLocalStorage extends LocalStorage {
  SafeSupabaseLocalStorage({
    required this.persistSessionKey,
    this.initTimeout = const Duration(seconds: 2),
  });

  final String persistSessionKey;
  final Duration initTimeout;

  SharedPreferences? _prefs;
  bool _prefsAvailable = false;
  bool _initAttempted = false;
  final Map<String, String> _memory = <String, String>{};

  Future<void> _ensurePrefs() async {
    if (_prefsAvailable || _initAttempted) return;
    _initAttempted = true;
    try {
      // initialize() now has built-in timeout and returns null on failure
      _prefs = await SharedPreferencesService.instance.initialize();
      if (_prefs != null) {
        _prefsAvailable = true;
        if (_memory.isNotEmpty) {
          final cached = _memory[persistSessionKey];
          if (cached != null) {
            await _prefs!.setString(persistSessionKey, cached);
          }
        }
      } else {
        _prefsAvailable = false;
        if (kDebugMode) {
          debugPrint(
            '⚠️ SafeSupabaseLocalStorage: SharedPreferences unavailable; using memory storage',
          );
        }
      }
    } catch (e) {
      _prefsAvailable = false;
      if (kDebugMode) {
        debugPrint(
          '⚠️ SafeSupabaseLocalStorage: SharedPreferences init failed; using memory storage ($e)',
        );
      }
      // Fall back to memory storage - no automatic restart
      // SQLite handles all app data now, SharedPreferences only for auth token
    }
  }

  @override
  Future<void> initialize() async {
    await _ensurePrefs();
  }

  @override
  Future<bool> hasAccessToken() async {
    await _ensurePrefs();
    if (_prefsAvailable) {
      return _prefs!.containsKey(persistSessionKey);
    }
    return _memory.containsKey(persistSessionKey);
  }

  @override
  Future<String?> accessToken() async {
    await _ensurePrefs();
    if (_prefsAvailable) {
      return _prefs!.getString(persistSessionKey);
    }
    return _memory[persistSessionKey];
  }

  @override
  Future<void> removePersistedSession() async {
    await _ensurePrefs();
    if (_prefsAvailable) {
      await _prefs!.remove(persistSessionKey);
    } else {
      _memory.remove(persistSessionKey);
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _ensurePrefs();
    if (_prefsAvailable) {
      await _prefs!.setString(persistSessionKey, persistSessionString);
    } else {
      _memory[persistSessionKey] = persistSessionString;
    }
  }
}

/// Safe Gotrue async storage to avoid SharedPreferences blocking on Android.
class SafeGotrueAsyncStorage extends GotrueAsyncStorage {
  SafeGotrueAsyncStorage({this.initTimeout = const Duration(seconds: 2)});

  final Duration initTimeout;
  SharedPreferences? _prefs;
  bool _prefsAvailable = false;
  bool _initAttempted = false;
  final Map<String, String> _memory = <String, String>{};

  Future<void> _ensurePrefs() async {
    if (_prefsAvailable || _initAttempted) return;
    _initAttempted = true;
    try {
      // initialize() now has built-in timeout and returns null on failure
      _prefs = await SharedPreferencesService.instance.initialize();
      if (_prefs != null) {
        _prefsAvailable = true;
        if (_memory.isNotEmpty) {
          for (final entry in _memory.entries) {
            await _prefs!.setString(entry.key, entry.value);
          }
        }
      } else {
        _prefsAvailable = false;
        if (kDebugMode) {
          debugPrint(
            '⚠️ SafeGotrueAsyncStorage: SharedPreferences unavailable; using memory storage',
          );
        }
      }
    } catch (e) {
      _prefsAvailable = false;
      if (kDebugMode) {
        debugPrint(
          '⚠️ SafeGotrueAsyncStorage: SharedPreferences init failed; using memory storage ($e)',
        );
      }
      // Fall back to memory storage - no automatic restart
      // SQLite handles all app data now, SharedPreferences only for auth token
    }
  }

  @override
  Future<String?> getItem({required String key}) async {
    await _ensurePrefs();
    if (_prefsAvailable) {
      return _prefs!.getString(key);
    }
    return _memory[key];
  }

  @override
  Future<void> removeItem({required String key}) async {
    await _ensurePrefs();
    if (_prefsAvailable) {
      await _prefs!.remove(key);
    } else {
      _memory.remove(key);
    }
  }

  @override
  Future<void> setItem({
    required String key,
    required String value,
  }) async {
    await _ensurePrefs();
    if (_prefsAvailable) {
      await _prefs!.setString(key, value);
    } else {
      _memory[key] = value;
    }
  }
}
