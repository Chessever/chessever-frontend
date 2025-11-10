import 'dart:async';

import 'package:chessever2/repository/local_storage/country_man/country_man_repository.dart';
import 'package:chessever2/repository/location/location_repository_provider.dart';
import 'package:country_picker/country_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final countryDropdownProvider =
    StateNotifierProvider<SelectedCountryNotifier, AsyncValue<Country>>(
      (ref) => SelectedCountryNotifier(ref),
    );

class SelectedCountryNotifier extends StateNotifier<AsyncValue<Country>> {
  SelectedCountryNotifier(this.ref) : super(AsyncValue.loading()) {
    _loadSavedCountry();
  }

  final Ref ref;

  Future<void> _loadSavedCountry() async {
    try {
      final savedValue =
          await ref.read(countryManRepository).getSavedCountryMan();

      if (savedValue != null && savedValue.isNotEmpty) {
        Country? matchedCountry;

        // Check if it's a legacy name format (starts with 'LEGACY:')
        if (savedValue.startsWith('LEGACY:')) {
          final legacyName = savedValue.substring(7); // Remove 'LEGACY:' prefix
          matchedCountry = CountryService().getAll().firstWhere(
                (c) => c.name.toLowerCase() == legacyName.toLowerCase(),
                orElse: () => CountryService().getAll().first,
              );

          // Migrate to new format by saving country code
          await ref
              .read(countryManRepository)
              .saveCountryMan(matchedCountry.countryCode);
        } else {
          // New format: country code (e.g., 'US', 'TR')
          matchedCountry = CountryService().findByCode(savedValue);
        }

        if (matchedCountry != null) {
          state = AsyncValue.data(matchedCountry);
          return;
        }
      }

      // No saved country or failed to find - use location-based detection
      final countryCode =
          await ref.read(locationRepositoryProvider).getCountryCode();
      final country = CountryService().findByCode(countryCode);
      state = AsyncValue.data(country ?? CountryService().getAll().first);
    } catch (e) {
      try {
        final country = CountryService().findByCode('US');
        state = AsyncValue.data(
          country ?? CountryService().findByName('United States')!,
        );
      } catch (e, st) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void selectCountry(String countryCode) {
    final country = CountryService().findByCode(countryCode);
    if (country != null) {
      // Update state immediately for instant UI response
      state = AsyncValue.data(country);
      // Persist in background (fire-and-forget)
      unawaited(
        ref.read(countryManRepository).saveCountryMan(country.countryCode),
      );
    } else {
      state = AsyncValue.data(CountryService().getAll().first);
      unawaited(
        ref
            .read(countryManRepository)
            .saveCountryMan(CountryService().getAll().first.countryCode),
      );
    }
  }

  void clearSelection() {
    // Update state immediately for instant UI response
    state = AsyncValue.data(CountryService().getAll().first);
    // Remove in background (fire-and-forget)
    unawaited(
      ref.read(countryManRepository).removeCountrySelection(),
    );
  }

  String getCountryName(String countryCode) {
    final country = CountryService().findByCode(countryCode);
    return country?.name ?? CountryService().getAll().first.name;
  }

  List<Country> getAllCountries() {
    return CountryService().getAll();
  }
}
