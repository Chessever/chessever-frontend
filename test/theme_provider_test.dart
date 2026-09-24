import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/theme/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = 'app.theme_mode.v1';

/// The service caches one SharedPreferences instance for the whole test run,
/// so each case writes (or clears) the key on that shared instance instead of
/// re-seeding the mock store.
Future<SharedPreferences> _prefs() async {
  final prefs = await SharedPreferencesService.instance.ensureInitialized();
  expect(prefs, isNotNull, reason: 'mock prefs must initialise');
  return prefs!;
}

/// Lets `_restore()` (fired from the constructor) finish its awaits.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUp(() async {
    await (await _prefs()).remove(_key);
  });

  group('ThemeModeNotifier restore', () {
    test('a user who never chose stays on dark (the default)', () async {
      final notifier = ThemeModeNotifier();
      expect(notifier.state, ThemeMode.dark);
      await _settle();
      expect(notifier.state, ThemeMode.dark);
      // Restoring must not write anything for a user who never opted in.
      expect((await _prefs()).getString(_key), isNull);
    });

    test('the dark value pinned by the dark-only builds restores as dark',
        () async {
      await (await _prefs()).setString(_key, 'dark');
      final notifier = ThemeModeNotifier();
      await _settle();
      expect(notifier.state, ThemeMode.dark);
    });

    test('restores a saved light choice', () async {
      await (await _prefs()).setString(_key, 'light');
      final notifier = ThemeModeNotifier();
      await _settle();
      expect(notifier.state, ThemeMode.light);
    });

    test('restores a saved Auto (system) choice', () async {
      await (await _prefs()).setString(_key, 'system');
      final notifier = ThemeModeNotifier();
      await _settle();
      expect(notifier.state, ThemeMode.system);
    });

    test('an unknown stored value falls back to dark', () async {
      await (await _prefs()).setString(_key, 'sepia');
      final notifier = ThemeModeNotifier();
      await _settle();
      expect(notifier.state, ThemeMode.dark);
    });
  });

  group('ThemeModeNotifier setTheme / toggle', () {
    test('setTheme updates state and persists the choice', () async {
      final notifier = ThemeModeNotifier();
      await _settle();

      notifier.setTheme(ThemeMode.light);
      await _settle();
      expect(notifier.state, ThemeMode.light);
      expect((await _prefs()).getString(_key), 'light');

      notifier.setTheme(ThemeMode.system);
      await _settle();
      expect(notifier.state, ThemeMode.system);
      expect((await _prefs()).getString(_key), 'system');
    });

    test('toggleTheme flips between dark and light', () async {
      final notifier = ThemeModeNotifier();
      await _settle();

      notifier.toggleTheme();
      await _settle();
      expect(notifier.state, ThemeMode.light);
      expect((await _prefs()).getString(_key), 'light');

      notifier.toggleTheme();
      await _settle();
      expect(notifier.state, ThemeMode.dark);
      expect((await _prefs()).getString(_key), 'dark');
    });

    test('a persisted choice survives a fresh notifier (app restart)',
        () async {
      final first = ThemeModeNotifier();
      await _settle();
      first.setTheme(ThemeMode.light);
      await _settle();

      // The prefs cache is warm, so the saved choice is the very first
      // state: no dark frame that fades to light.
      final second = ThemeModeNotifier();
      expect(second.state, ThemeMode.light);
      await _settle();
      expect(second.state, ThemeMode.light);
    });
  });
}
