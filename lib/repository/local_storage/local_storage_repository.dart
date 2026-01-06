import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton class to hold the pre-initialized SharedPreferences instance.
/// This prevents multiple calls to SharedPreferences.getInstance() which can
/// cause hangs on Android when the preferences file is corrupted or being
/// accessed by multiple isolates.
class SharedPreferencesService {
  SharedPreferencesService._();
  static final SharedPreferencesService _instance = SharedPreferencesService._();
  static SharedPreferencesService get instance => _instance;

  SharedPreferences? _prefs;

  /// Returns the cached SharedPreferences instance.
  /// Throws if not initialized - call initialize() first in main().
  SharedPreferences get prefs {
    if (_prefs == null) {
      throw StateError(
        'SharedPreferencesService not initialized. '
        'Call SharedPreferencesService.instance.initialize() in main() first.',
      );
    }
    return _prefs!;
  }

  /// Initialize SharedPreferences once at app startup.
  /// Should be called in main() before runApp().
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Check if the service has been initialized.
  bool get isInitialized => _prefs != null;
}

final sharedPreferencesRepository = AutoDisposeProvider<AppSharedPreferences>((
  ref,
) {
  return AppSharedPreferences();
});

class AppSharedPreferences {
  AppSharedPreferences();

  SharedPreferences get _prefs => SharedPreferencesService.instance.prefs;

  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  Future<int?> getInt(String key) async {
    return _prefs.getInt(key);
  }

  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  Future<bool?> getBool(String key) async {
    return _prefs.getBool(key);
  }

  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  Future<String?> getString(String key) async {
    return _prefs.getString(key);
  }

  Future<void> setStringList(String key, List<String> value) async {
    await _prefs.setStringList(key, value);
  }

  Future<List<String>> getStringList(String key) async {
    return _prefs.getStringList(key) ?? [];
  }

  Future<void> removeData(String key) async {
    await _prefs.remove(key);
  }
}
