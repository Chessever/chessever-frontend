import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../repository/local_storage/notifications_repository/notifications_repository.dart';
import '../services/push_notifications_service.dart';

class NotificationsSettings {
  final bool enabled;

  const NotificationsSettings({required this.enabled});

  NotificationsSettings copyWith({bool? enabled}) {
    return NotificationsSettings(enabled: enabled ?? this.enabled);
  }
}

class NotificationsSettingsNotifier
    extends StateNotifier<NotificationsSettings> {
  NotificationsSettingsNotifier(this.ref)
    : super(const NotificationsSettings(enabled: false)) {
    // Load saved settings when initialized
    _loadSavedSettings();
  }

  final Ref ref;

  Future<void> _loadSavedSettings() async {
    try {
      final savedSettings =
          await ref.read(notificationsRepository).loadNotificationsSettings();
      state = savedSettings;
      unawaited(
        PushNotificationsService.instance.setPushEnabled(savedSettings.enabled),
      );
    } catch (error, _) {
      // Keep default settings on error
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    _saveSettings();
    if (enabled) {
      final granted =
          await PushNotificationsService.instance.requestPermissionWithDialog();
      if (!granted) {
        state = state.copyWith(enabled: false);
        _saveSettings();
      }
      return;
    }
    unawaited(PushNotificationsService.instance.setPushEnabled(false));
  }

  Future<void> _saveSettings() async {
    try {
      await ref.read(notificationsRepository).saveNotificationsSettings(state);
    } catch (error, _) {
      // Handle error if needed
    }
  }
}

final notificationsSettingsProvider =
    StateNotifierProvider<NotificationsSettingsNotifier, NotificationsSettings>(
      (ref) => NotificationsSettingsNotifier(ref),
    );
