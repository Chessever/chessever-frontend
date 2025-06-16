import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../services/settings_service.dart';

// Define supported locales
class SupportedLocales {
  static const english = Locale('en');

  // List of supported locales - we only have English for now
  static const values = [english];
}

// Create a state notifier for locale management
class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(SupportedLocales.english) {
    // Load saved locale when initialized
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    final savedLocale = await SettingsService.loadLocale();
    if (savedLocale != null) {
      state = savedLocale;
    }
  }

  void setLocale(Locale locale) {
    state = locale;
    _saveLocale();
  }

  Future<void> _saveLocale() async {
    await SettingsService.saveLocale(state);
  }
}

// Create a provider for Locale state
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

// Create a provider that exposes Locale name
final localeNameProvider = Provider<String>((ref) {
  final locale = ref.watch(localeProvider);

  switch (locale.languageCode) {
    case 'en':
      return 'English';
    default:
      return 'English';
  }
});
