import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/foundation.dart';

class AutoPinPreferences {
  final bool favoritePlayersAutoPinEnabled;
  final bool countrymenAutoPinEnabled;

  const AutoPinPreferences({
    this.favoritePlayersAutoPinEnabled = true,
    this.countrymenAutoPinEnabled = false,
  });

  static const defaults = AutoPinPreferences();

  AutoPinPreferences copyWith({
    bool? favoritePlayersAutoPinEnabled,
    bool? countrymenAutoPinEnabled,
  }) {
    return AutoPinPreferences(
      favoritePlayersAutoPinEnabled:
          favoritePlayersAutoPinEnabled ?? this.favoritePlayersAutoPinEnabled,
      countrymenAutoPinEnabled:
          countrymenAutoPinEnabled ?? this.countrymenAutoPinEnabled,
    );
  }
}

class AutoPinPreferencesRepository {
  static const String _prefsKey = 'auto_pin_preferences';
  static const String _tourDisabledKeyPrefix = 'auto_pin_disabled_';
  static const String _legacyTourKeyPrefix = 'autoPinFavGames_';

  final AppDatabase _db;

  AutoPinPreferencesRepository(this._db);

  static String _encodeBool(bool value) => value ? '1' : '0';
  static bool _decodeBool(String value) => value == '1';

  // ---- Global preferences (user-scoped) ----

  Future<AutoPinPreferences> loadPreferences(String? userId) async {
    try {
      final entry = await _db.getCache(
        key: _prefsKey,
        userId: userId,
      );
      if (entry == null) return AutoPinPreferences.defaults;

      final map = jsonDecode(entry.value) as Map<String, dynamic>;
      return AutoPinPreferences(
        favoritePlayersAutoPinEnabled:
            map['favoritePlayersAutoPinEnabled'] as bool? ??
                AutoPinPreferences.defaults.favoritePlayersAutoPinEnabled,
        countrymenAutoPinEnabled:
            map['countrymenAutoPinEnabled'] as bool? ??
                AutoPinPreferences.defaults.countrymenAutoPinEnabled,
      );
    } catch (e) {
      debugPrint('[AutoPinPrefs] Error loading: $e');
      return AutoPinPreferences.defaults;
    }
  }

  Future<void> _savePreferences(
    AutoPinPreferences prefs,
    String? userId,
  ) async {
    try {
      final json = jsonEncode({
        'favoritePlayersAutoPinEnabled': prefs.favoritePlayersAutoPinEnabled,
        'countrymenAutoPinEnabled': prefs.countrymenAutoPinEnabled,
      });
      await _db.setCache(key: _prefsKey, value: json, userId: userId);
    } catch (e) {
      debugPrint('[AutoPinPrefs] Error saving: $e');
    }
  }

  Future<void> setFavoritePlayersAutoPin(
    bool enabled,
    String? userId,
  ) async {
    final current = await loadPreferences(userId);
    await _savePreferences(
      current.copyWith(favoritePlayersAutoPinEnabled: enabled),
      userId,
    );
  }

  Future<void> setCountrymenAutoPin(bool enabled, String? userId) async {
    final current = await loadPreferences(userId);
    await _savePreferences(
      current.copyWith(countrymenAutoPinEnabled: enabled),
      userId,
    );
  }

  // ---- Per-tournament auto-pin disable (user-scoped) ----

  String _tourDisabledKey(String tourId) =>
      '$_tourDisabledKeyPrefix$tourId';

  String _legacyTourKey(String tourId) =>
      '$_legacyTourKeyPrefix$tourId';

  Future<bool> getTournamentAutoPinDisabled(
    String tourId,
    String? userId,
  ) async {
    try {
      final entry = await _db.getCache(
        key: _tourDisabledKey(tourId),
        userId: userId,
      );

      if (entry != null) {
        return _decodeBool(entry.value);
      }

      // Compatibility fallback: read legacy unscoped key
      final legacyValue = await _db.getBool(_legacyTourKey(tourId));
      if (legacyValue != null) {
        // Copy to user-scoped cache
        await _db.setCache(
          key: _tourDisabledKey(tourId),
          value: _encodeBool(legacyValue),
          userId: userId,
        );
        return legacyValue;
      }

      return false;
    } catch (e) {
      debugPrint('[AutoPinPrefs] Error reading tour disabled: $e');
      return false;
    }
  }

  Future<void> setTournamentAutoPinDisabled(
    String tourId,
    bool disabled,
    String? userId,
  ) async {
    try {
      await _db.setCache(
        key: _tourDisabledKey(tourId),
        value: _encodeBool(disabled),
        userId: userId,
      );
    } catch (e) {
      debugPrint('[AutoPinPrefs] Error setting tour disabled: $e');
    }
  }
}
