import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../localization/locale_provider.dart';
import '../providers/board_settings_provider.dart';
import '../providers/notifications_settings_provider.dart';
import '../providers/timezone_provider.dart';
import '../services/settings_service.dart';

/// A manager class to handle initialization of all settings
class SettingsManager {
  /// Initialize all settings at app startup
  static Future<void> initializeSettings(WidgetRef ref) async {
    // Load saved board settings if available
    final savedBoardSettings = await SettingsService.loadBoardSettings();
    if (savedBoardSettings != null) {
      ref.read(boardSettingsProvider.notifier).state = savedBoardSettings;
    }

    // Load saved notifications settings if available
    final savedNotificationsSettings =
        await SettingsService.loadNotificationsSettings();
    if (savedNotificationsSettings != null) {
      ref.read(notificationsSettingsProvider.notifier).state =
          savedNotificationsSettings;
    }

    // Load saved timezone if available
    final savedTimezone = await SettingsService.loadTimezone();
    if (savedTimezone != null) {
      ref.read(timezoneProvider.notifier).state = savedTimezone;
    }

    // Load saved locale if available
    final savedLocale = await SettingsService.loadLocale();
    if (savedLocale != null) {
      ref.read(localeProvider.notifier).state = savedLocale;
    }
  }
}
