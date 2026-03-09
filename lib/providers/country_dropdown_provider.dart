import 'dart:async';

import 'package:chessever2/repository/local_storage/country_man/country_man_repository.dart';
import 'package:chessever2/repository/location/location_repository_provider.dart';
import 'package:country_picker/country_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final countryDropdownProvider =
    StateNotifierProvider<SelectedCountryNotifier, AsyncValue<Country>>(
      (ref) => SelectedCountryNotifier(ref),
    );

/// Temporary country selection for countrymen screen exploration.
/// This is NOT persisted - it's session-only.
/// When null, uses the persisted country from countryDropdownProvider.
final temporaryCountryProvider = StateProvider<Country?>((ref) => null);

/// Effective country for countrymen screen: temporary takes precedence over persisted.
/// Use this provider in countrymen-related screens and providers.
final effectiveCountryProvider = Provider<AsyncValue<Country>>((ref) {
  final tempCountry = ref.watch(temporaryCountryProvider);
  if (tempCountry != null) {
    return AsyncValue.data(tempCountry);
  }
  return ref.watch(countryDropdownProvider);
});

Country _defaultCountry() {
  final service = CountryService();
  return service.findByCode('US') ??
      service.findByName('United States') ??
      service.getAll().first;
}

class SelectedCountryNotifier extends StateNotifier<AsyncValue<Country>> {
  SelectedCountryNotifier(this.ref) : super(AsyncValue.loading()) {
    _loadSavedCountry();
  }

  final Ref ref;

  Future<void> _loadSavedCountry() async {
    try {
      // Read from SQLite only for instant UI render on cold start.
      // The existing syncFromSupabase() in auth_state_listener corrects
      // any stale data shortly after authentication completes.
      final savedValue =
          await ref.read(countryManRepository).getSavedCountryManLocal();

      if (savedValue != null && savedValue.isNotEmpty) {
        Country? matchedCountry;

        // Check if it's a legacy name format (starts with 'LEGACY:')
        if (savedValue.startsWith('LEGACY:')) {
          final legacyName = savedValue.substring(7); // Remove 'LEGACY:' prefix
          matchedCountry = CountryService().getAll().firstWhere(
            (c) => c.name.toLowerCase() == legacyName.toLowerCase(),
            orElse: _defaultCountry,
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
      state = AsyncValue.data(country ?? _defaultCountry());
    } catch (e) {
      try {
        state = AsyncValue.data(_defaultCountry());
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
      // Invalid country code should never clobber an existing valid state.
      state = AsyncValue.data(state.valueOrNull ?? _defaultCountry());
    }
  }

  void clearSelection() {
    // Update state immediately for instant UI response
    state = AsyncValue.data(_defaultCountry());
    // Remove in background (fire-and-forget)
    unawaited(ref.read(countryManRepository).removeCountrySelection());
  }

  /// Clear local state only (for logout) without touching Supabase.
  /// User's preference persists in Supabase for next login.
  void clearLocalOnly() {
    state = AsyncValue.data(_defaultCountry());
    unawaited(ref.read(countryManRepository).clearLocalCacheOnly());
  }

  /// Reload country selection from Supabase (source of truth)
  /// Call this after user authentication to fetch their saved selection
  Future<void> syncFromSupabase() async {
    try {
      final savedValue =
          await ref.read(countryManRepository).getSavedCountryMan();

      if (savedValue != null && savedValue.isNotEmpty) {
        Country? matchedCountry;

        // Check if it's a legacy name format (starts with 'LEGACY:')
        if (savedValue.startsWith('LEGACY:')) {
          final legacyName = savedValue.substring(7);
          matchedCountry = CountryService().getAll().firstWhere(
            (c) => c.name.toLowerCase() == legacyName.toLowerCase(),
            orElse: _defaultCountry,
          );
          // Migrate to new format
          await ref
              .read(countryManRepository)
              .saveCountryMan(matchedCountry.countryCode);
        } else {
          matchedCountry = CountryService().findByCode(savedValue);
        }

        if (matchedCountry != null) {
          state = AsyncValue.data(matchedCountry);
          return;
        }
      }

      // No saved country found in Supabase - use location-based detection
      final countryCode =
          await ref.read(locationRepositoryProvider).getCountryCode();
      final country = CountryService().findByCode(countryCode);
      state = AsyncValue.data(country ?? _defaultCountry());
    } catch (e) {
      // Keep existing state on error
    }
  }

  String getCountryName(String countryCode) {
    final country = CountryService().findByCode(countryCode);
    return country?.name ?? _defaultCountry().name;
  }

  List<Country> getAllCountries() {
    return CountryService().getAll();
  }
}
