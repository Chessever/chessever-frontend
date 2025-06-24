import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../repository/local_storage/language_repository/language_repository.dart';

// Define supported locales
class SupportedLocales {
  static const english = Locale('en');

  // List of supported locales - we only have English for now
  static const values = [english];
}

// Create a state notifier for locale management
class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier(this.ref) : super(SupportedLocales.english) {
    // Load saved locale when initialized
    _loadSavedLocale();
  }

  final Ref ref;

  Future<void> _loadSavedLocale() async {
    try {
      final savedLocale = await ref.read(languageRepository).loadLanguage();
      state = savedLocale;
    } catch (error, _) {
      // Keep default locale on error
      print('Error loading saved locale: $error');
    }
  }

  void setLocale(Locale locale) {
    if (state.languageCode != locale.languageCode) {
      state = locale;
      _saveLocale();
    }
  }

  Future<void> _saveLocale() async {
    try {
      await ref.read(languageRepository).saveLanguage(state);
      print('Locale saved successfully: ${state.languageCode}');
    } catch (error, _) {
      print('Error saving locale: $error');
    }
  }
}

// Create a provider for Locale state
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier(ref);
});

// Create a provider that exposes Locale name
final localeNameProvider = Provider<String>((ref) {
  final locale = ref.watch(localeProvider);
  final repository = ref.read(languageRepository);

  final language = repository.getLanguageFromLocale(locale);
  return language.name;
});
