import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
      final db = ref.read(appDatabaseProvider);
      final language = getLanguageFromLocale(locale);
      await db.setInt(_languageKey, language.index);
    } catch (error, _) {
      // Local storage failure is not critical
    }
  }

  Future<Locale> loadLanguage() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final index = await db.getInt(_languageKey);

      if (index == null) {
        return SupportedLanguage.english.locale;
      }

      if (index >= 0 && index < SupportedLanguage.values.length) {
        return SupportedLanguage.values[index].locale;
      } else {
        return SupportedLanguage.english.locale;
      }
    } catch (error, _) {
      // Local storage failure - return default
      return SupportedLanguage.english.locale;
    }
  }
}
