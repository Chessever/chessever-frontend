import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:shared_preferences/shared_preferences.dart' show SharedPreferences;

/// Singleton class to hold the pre-initialized SharedPreferences instance.
/// This prevents multiple calls to SharedPreferences.getInstance() which can
/// cause hangs on Android when the preferences file is corrupted or being
/// accessed by multiple isolates.
class SharedPreferencesService {
  SharedPreferencesService._();
  static final SharedPreferencesService _instance = SharedPreferencesService._();
  static SharedPreferencesService get instance => _instance;

  SharedPreferences? _prefs;
  Future<SharedPreferences>? _initFuture;

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
  Future<SharedPreferences> initialize() async {
    if (_prefs != null) return _prefs!;
    _initFuture ??= SharedPreferences.getInstance();
    _prefs = await _initFuture!;
    return _prefs!;
  }

  /// Ensure preferences are initialized, even if main() didn't await it.
  Future<SharedPreferences> ensureInitialized() async {
    if (_prefs != null) return _prefs!;
    return initialize();
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

  Future<SharedPreferences> _getPrefs() async =>
      SharedPreferencesService.instance.ensureInitialized();

  Future<void> setInt(String key, int value) async {
    final prefs = await _getPrefs();
    await prefs.setInt(key, value);
  }

  Future<int?> getInt(String key) async {
    final prefs = await _getPrefs();
    return prefs.getInt(key);
  }

  Future<void> setBool(String key, bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(key, value);
  }

  Future<bool?> getBool(String key) async {
    final prefs = await _getPrefs();
    return prefs.getBool(key);
  }

  Future<void> setString(String key, String value) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, value);
  }

  Future<String?> getString(String key) async {
    final prefs = await _getPrefs();
    return prefs.getString(key);
  }

  Future<void> setStringList(String key, List<String> value) async {
    final prefs = await _getPrefs();
    await prefs.setStringList(key, value);
  }

  Future<List<String>> getStringList(String key) async {
    final prefs = await _getPrefs();
    return prefs.getStringList(key) ?? [];
  }

  Future<void> removeData(String key) async {
    final prefs = await _getPrefs();
    await prefs.remove(key);
  }
}
