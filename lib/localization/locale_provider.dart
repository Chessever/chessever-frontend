import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Define supported locales
class SupportedLocales {
  static const english = Locale('en');

  // List of supported locales - we only have English for now
  static const values = [english];
}

// Create a state notifier for locale management
class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(SupportedLocales.english);

  void setLocale(Locale locale) {
    state = locale;
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
