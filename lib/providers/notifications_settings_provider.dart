import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../services/settings_service.dart';

class NotificationsSettings {
  final bool enabled;
  final bool gameInvites;
  final bool tournamentReminders;
  final bool friendActivity;

  const NotificationsSettings({
    required this.enabled,
    required this.gameInvites,
    required this.tournamentReminders,
    required this.friendActivity,
  });

  NotificationsSettings copyWith({
    bool? enabled,
    bool? gameInvites,
    bool? tournamentReminders,
    bool? friendActivity,
  }) {
    return NotificationsSettings(
      enabled: enabled ?? this.enabled,
      gameInvites: gameInvites ?? this.gameInvites,
      tournamentReminders: tournamentReminders ?? this.tournamentReminders,
      friendActivity: friendActivity ?? this.friendActivity,
    );
  }
}

class NotificationsSettingsNotifier
    extends StateNotifier<NotificationsSettings> {
  NotificationsSettingsNotifier()
    : super(
        const NotificationsSettings(
          enabled: false,
          gameInvites: true,
          tournamentReminders: true,
          friendActivity: false,
        ),
      ) {
    // Load saved settings when initialized
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final savedSettings = await SettingsService.loadNotificationsSettings();
    if (savedSettings != null) {
      state = savedSettings;
    }
  }

  void toggleEnabled() {
    state = state.copyWith(enabled: !state.enabled);
    _saveSettings();
  }

  void toggleGameInvites() {
    state = state.copyWith(gameInvites: !state.gameInvites);
    _saveSettings();
  }

  void toggleTournamentReminders() {
    state = state.copyWith(tournamentReminders: !state.tournamentReminders);
    _saveSettings();
  }

  void toggleFriendActivity() {
    state = state.copyWith(friendActivity: !state.friendActivity);
    _saveSettings();
  }

  Future<void> _saveSettings() async {
    await SettingsService.saveNotificationsSettings(state);
  }
}

final notificationsSettingsProvider =
    StateNotifierProvider<NotificationsSettingsNotifier, NotificationsSettings>(
      (ref) => NotificationsSettingsNotifier(),
    );
