import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../providers/timezone_provider.dart';
import '../../../widgets/timezone_settings_dialog.dart';

final timezoneRepository = AutoDisposeProvider<_TimezoneRepository>((ref) {
  return _TimezoneRepository(ref);
});

class _TimezoneRepository {
  _TimezoneRepository(this.ref);

  final Ref ref;
  static const String _timezoneKey = 'app_timezone';
  static const String _timezoneIdKey = 'app_timezone_id';

  Future<void> saveTimezone(TimeZone timezone) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.setInt(_timezoneKey, timezone.index);

      // Also save the current selected timezone ID
      final selectedId = ref.read(selectedTimezoneIdProvider);
      await db.setString(_timezoneIdKey, selectedId);
    } catch (error, _) {
      // Local storage failure is not critical
    }
  }

  Future<TimeZone> loadTimezone() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final index = await db.getInt(_timezoneKey);

      // Load saved timezone ID if it exists
      final savedId = await db.getString(_timezoneIdKey);
      if (savedId != null) {
        // Update the ID provider
        ref.read(selectedTimezoneIdProvider.notifier).state = savedId;
      }

      if (index == null) {
        return TimeZone.local;
      }

      if (index >= 0 && index < TimeZone.values.length) {
        return TimeZone.values[index];
      } else {
        return TimeZone.local;
      }
    } catch (error, _) {
      // Local storage failure - return default
      return TimeZone.local;
    }
  }
}
