import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../repository/local_storage/notifications_repository/notifications_repository.dart';

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
    } catch (error, _) {
      // Keep default settings on error
    }
  }

  void toggleEnabled() {
    state = state.copyWith(enabled: !state.enabled);
    _saveSettings();
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
