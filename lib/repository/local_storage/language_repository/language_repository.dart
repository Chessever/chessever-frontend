import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final languageRepository = AutoDisposeProvider<_LanguageRepository>((ref) {
  return _LanguageRepository(ref);
});

enum SupportedLanguage { english, deutsch, chinese, spanish, french }

extension SupportedLanguageExtension on SupportedLanguage {
  String get name {
    switch (this) {
      case SupportedLanguage.english:
        return 'English';
      case SupportedLanguage.deutsch:
        return 'Deutsch';
      case SupportedLanguage.chinese:
        return '中文';
      case SupportedLanguage.spanish:
        return 'Español';
      case SupportedLanguage.french:
        return 'Français';
    }
  }

  Locale get locale {
    switch (this) {
      case SupportedLanguage.english:
        return const Locale('en');
      case SupportedLanguage.deutsch:
        return const Locale('de');
      case SupportedLanguage.chinese:
        return const Locale('zh');
      case SupportedLanguage.spanish:
        return const Locale('es');
      case SupportedLanguage.french:
        return const Locale('fr');
    }
  }
}

class _LanguageRepository {
  _LanguageRepository(this.ref);

  final Ref ref;
  static const String _languageKey = 'app_language';

  SupportedLanguage getLanguageFromLocale(Locale locale) {
    for (final language in SupportedLanguage.values) {
      if (language.locale.languageCode == locale.languageCode) {
        return language;
      }
    }
    // Default to English if not found
    return SupportedLanguage.english;
  }

  Future<void> saveLanguage(Locale locale) async {
    try {
      final prefs = ref.read(sharedPreferencesRepository);
      final language = getLanguageFromLocale(locale);

      // Store the language index in preferences
      await prefs.setString(_languageKey, language.index.toString());

      // Double-check that the value was stored
      final storedValue = await prefs.getString(_languageKey);
      if (storedValue != language.index.toString()) {
        print(
          'Warning: Language preference might not have been saved correctly.',
        );
        print('Expected: ${language.index}, Actual: $storedValue');

        // Fallback: try storing directly
        final directPrefs = await SharedPreferences.getInstance();
        await directPrefs.setString(_languageKey, language.index.toString());
      }
    } catch (error, _) {
      print('Error saving language: $error');

      // Fallback: try storing directly
      try {
        final directPrefs = await SharedPreferences.getInstance();
        final language = getLanguageFromLocale(locale);
        await directPrefs.setString(_languageKey, language.index.toString());
      } catch (e) {
        print('Fallback also failed: $e');
      }

      rethrow;
    }
  }

  Future<Locale> loadLanguage() async {
    try {
      final prefs = ref.read(sharedPreferencesRepository);
      final indexString = await prefs.getString(_languageKey);

      if (indexString == null) {
        // Try direct access as fallback
        final directPrefs = await SharedPreferences.getInstance();
        final directValue = directPrefs.getString(_languageKey);

        if (directValue != null) {
          final index = int.tryParse(directValue);
          if (index != null &&
              index >= 0 &&
              index < SupportedLanguage.values.length) {
            return SupportedLanguage.values[index].locale;
          }
        }

        // Default to English if no language preference is saved
        return SupportedLanguage.english.locale;
      }

      final index = int.tryParse(indexString);
      if (index != null &&
          index >= 0 &&
          index < SupportedLanguage.values.length) {
        return SupportedLanguage.values[index].locale;
      } else {
        // Default to English if index is invalid
        return SupportedLanguage.english.locale;
      }
    } catch (error, _) {
      print('Error loading language: $error');

      // Try direct access as fallback
      try {
        final directPrefs = await SharedPreferences.getInstance();
        final directValue = directPrefs.getString(_languageKey);

        if (directValue != null) {
          final index = int.tryParse(directValue);
          if (index != null &&
              index >= 0 &&
              index < SupportedLanguage.values.length) {
            return SupportedLanguage.values[index].locale;
          }
        }
      } catch (e) {
        print('Fallback also failed: $e');
      }

      // Default to English on error
      return SupportedLanguage.english.locale;
    }
  }
}
