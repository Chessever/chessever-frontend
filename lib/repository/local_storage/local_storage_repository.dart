import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesRepository = AutoDisposeProvider<_SharedPreferences>((
  ref,
) {
  return _SharedPreferences();
});

class _SharedPreferences {
  _SharedPreferences();

  Future<void> setString(String key, String value) async {
    try {
      final prefs = SharedPreferencesAsync();
      await prefs.setString(key, value);
    } catch (error, _) {
      rethrow;
    }
  }

  Future<String?> getString(String key) async {
    try {
      final prefs = SharedPreferencesAsync();
      return prefs.getString(key);
    } catch (error, _) {
      rethrow;
    }
  }

  Future<void> setStringList(String key, List<String> value) async {
    try {
      final prefs = SharedPreferencesAsync();
      await prefs.setStringList(key, value);
    } catch (error, _) {
      rethrow;
    }
  }

  Future<List<String>> getStringList(String key) async {
    try {
      final prefs = SharedPreferencesAsync();
      return (await prefs.getStringList(key)) ?? [];
    } catch (error, _) {
      rethrow;
    }
  }
}
