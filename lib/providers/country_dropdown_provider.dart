import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:country_picker/country_picker.dart';

// Generate the provider code
part 'country_dropdown_provider.g.dart';

// State class for the country dropdown
class CountryDropdownState {
  final String? selectedCountryCode;
  final bool isDropdownOpen;
  final List<Country> countries;

  CountryDropdownState({
    this.selectedCountryCode,
    this.isDropdownOpen = false,
    List<Country>? countries,
  }) : countries = countries ?? CountryService().getAll();

  CountryDropdownState copyWith({
    String? selectedCountryCode,
    bool? isDropdownOpen,
    List<Country>? countries,
  }) {
    return CountryDropdownState(
      selectedCountryCode: selectedCountryCode ?? this.selectedCountryCode,
      isDropdownOpen: isDropdownOpen ?? this.isDropdownOpen,
      countries: countries ?? this.countries,
    );
  }
}

// Provider for a specific country dropdown instance
@riverpod
class CountryDropdownNotifier extends _$CountryDropdownNotifier {
  @override
  CountryDropdownState build({String? initialCountry}) {
    final countries = CountryService().getAll();

    // Default to USA if no initial country is specified
    String defaultCountryCode = "US";

    // Validate initialCountry or use default
    String? validCountryCode = initialCountry;
    if (initialCountry == null) {
      validCountryCode = defaultCountryCode;
    } else if (!countries.any(
      (country) => country.countryCode == initialCountry,
    )) {
      validCountryCode = defaultCountryCode;
    }

    return CountryDropdownState(
      selectedCountryCode: validCountryCode,
      countries: countries,
    );
  }

  // Update selected country
  void selectCountry(String countryCode) {
    state = state.copyWith(
      selectedCountryCode: countryCode,
      isDropdownOpen: false,
    );
  }

  // Toggle dropdown state
  void setDropdownState(bool isOpen) {
    state = state.copyWith(isDropdownOpen: isOpen);
  }
}
