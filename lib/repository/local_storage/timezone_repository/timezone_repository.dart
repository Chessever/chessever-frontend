import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
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
      final prefs = ref.read(sharedPreferencesRepository);
      await prefs.setString(_timezoneKey, timezone.index.toString());

      // Also save the current selected timezone ID
      final selectedId = ref.read(selectedTimezoneIdProvider);
      await prefs.setString(_timezoneIdKey, selectedId);
    } catch (error, _) {
      rethrow;
    }
  }

  Future<TimeZone> loadTimezone() async {
    try {
      final prefs = ref.read(sharedPreferencesRepository);
      final indexString = await prefs.getString(_timezoneKey);

      // Load saved timezone ID if it exists
      final savedId = await prefs.getString(_timezoneIdKey);
      if (savedId != null) {
        // Update the ID provider
        ref.read(selectedTimezoneIdProvider.notifier).state = savedId;
      }

      if (indexString == null) {
        // Default to Local if no timezone preference is saved
        return TimeZone.local;
      }

      final index = int.tryParse(indexString);
      if (index != null && index >= 0 && index < TimeZone.values.length) {
        return TimeZone.values[index];
      } else {
        // Default to Local if index is invalid
        return TimeZone.local;
      }
    } catch (error, _) {
      // Default to Local on error
      return TimeZone.local;
    }
  }
}
