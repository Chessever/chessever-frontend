import 'package:chessever2/repository/sqlite/app_database.dart';
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
  static const String _notificationsEnabledKey = 'notifications_enabled';

  Future<void> saveNotificationsSettings(NotificationsSettings settings) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.setBool(_notificationsEnabledKey, settings.enabled);
    } catch (error, _) {
      // Local storage failure is not critical
    }
  }

  Future<NotificationsSettings> loadNotificationsSettings() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final enabled = await db.getBool(_notificationsEnabledKey);
      return NotificationsSettings(enabled: enabled ?? false);
    } catch (error, _) {
      // Local storage failure - return default
      return const NotificationsSettings(enabled: false);
    }
  }
}
