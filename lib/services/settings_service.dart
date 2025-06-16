import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/board_settings_provider.dart';
import '../providers/notifications_settings_provider.dart';
import '../providers/timezone_provider.dart';

/// A service class for persisting user settings to device storage
class SettingsService {
  static const String _boardSettingsKey = 'board_settings';
  static const String _notificationsSettingsKey = 'notifications_settings';
  static const String _timezoneKey = 'timezone';
  static const String _localeKey = 'locale';

  // Save board settings
  static Future<void> saveBoardSettings(BoardSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {
      'boardColorValue': settings.boardColor.value,
      'showEvaluationBar': settings.showEvaluationBar,
      'soundEnabled': settings.soundEnabled,
      'pieceStyle': settings.pieceStyle.index,
    };
    await prefs.setString(_boardSettingsKey, jsonEncode(data));
  }

  // Load board settings
  static Future<BoardSettings?> loadBoardSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final String? settingsString = prefs.getString(_boardSettingsKey);

    if (settingsString == null) {
      return null;
    }

    try {
      final Map<String, dynamic> data = jsonDecode(settingsString);
      return BoardSettings(
        boardColor: Color(data['boardColorValue']),
        showEvaluationBar: data['showEvaluationBar'],
        soundEnabled: data['soundEnabled'],
        pieceStyle: PieceStyle.values[data['pieceStyle']],
      );
    } catch (e) {
      return null;
    }
  }

  // Save notifications settings
  static Future<void> saveNotificationsSettings(
    NotificationsSettings settings,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {
      'enabled': settings.enabled,
      'gameInvites': settings.gameInvites,
      'tournamentReminders': settings.tournamentReminders,
      'friendActivity': settings.friendActivity,
    };
    await prefs.setString(_notificationsSettingsKey, jsonEncode(data));
  }

  // Load notifications settings
  static Future<NotificationsSettings?> loadNotificationsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final String? settingsString = prefs.getString(_notificationsSettingsKey);

    if (settingsString == null) {
      return null;
    }

    try {
      final Map<String, dynamic> data = jsonDecode(settingsString);
      return NotificationsSettings(
        enabled: data['enabled'],
        gameInvites: data['gameInvites'],
        tournamentReminders: data['tournamentReminders'],
        friendActivity: data['friendActivity'],
      );
    } catch (e) {
      return null;
    }
  }

  // Save timezone
  static Future<void> saveTimezone(TimeZone timezone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timezoneKey, timezone.index);
  }

  // Load timezone
  static Future<TimeZone?> loadTimezone() async {
    final prefs = await SharedPreferences.getInstance();
    final int? timezoneIndex = prefs.getInt(_timezoneKey);

    if (timezoneIndex == null || timezoneIndex >= TimeZone.values.length) {
      return null;
    }

    return TimeZone.values[timezoneIndex];
  }

  // Save locale
  static Future<void> saveLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
  }

  // Load locale
  static Future<Locale?> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final String? languageCode = prefs.getString(_localeKey);

    if (languageCode == null) {
      return null;
    }

    return Locale(languageCode);
  }
}
