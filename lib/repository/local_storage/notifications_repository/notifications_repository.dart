import 'dart:convert';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../providers/notifications_settings_provider.dart';

final notificationsRepository = AutoDisposeProvider<_NotificationsRepository>((
  ref,
) {
  return _NotificationsRepository(ref);
});

class _NotificationsRepository {
  _NotificationsRepository(this.ref);

  final Ref ref;
  static const String _notificationsSettingsKey = 'notifications_settings';

  Future<void> saveNotificationsSettings(NotificationsSettings settings) async {
    try {
      final prefs = ref.read(sharedPreferencesRepository);
      final Map<String, dynamic> data = {'enabled': settings.enabled};
      await prefs.setString(_notificationsSettingsKey, jsonEncode(data));
    } catch (error, _) {
      rethrow;
    }
  }

  Future<NotificationsSettings> loadNotificationsSettings() async {
    try {
      final prefs = ref.read(sharedPreferencesRepository);
      final String? settingsString = await prefs.getString(
        _notificationsSettingsKey,
      );

      if (settingsString == null) {
        // Return default settings if none are saved
        return const NotificationsSettings(enabled: false);
      }

      try {
        final Map<String, dynamic> data = jsonDecode(settingsString);
        return NotificationsSettings(enabled: data['enabled'] ?? false);
      } catch (e) {
        // Return default settings on parse error
        return const NotificationsSettings(enabled: false);
      }
    } catch (error, _) {
      // Return default settings on error
      return const NotificationsSettings(enabled: false);
    }
  }
}
