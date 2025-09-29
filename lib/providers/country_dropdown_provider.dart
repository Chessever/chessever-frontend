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
      final savedName =
          await ref.read(countryManRepository).getSavedCountryMan();
      if (savedName != null && savedName.isNotEmpty) {
        final matchedCountry = CountryService().getAll().firstWhere(
          (c) => c.name.toLowerCase() == savedName.toLowerCase(),
          orElse: () => CountryService().getAll().first,
        );
        state = AsyncValue.data(matchedCountry);
      } else {
        final countryCode =
            await ref.read(locationRepositoryProvider).getCountryCode();
        final country = CountryService().findByCode(countryCode);
        state = AsyncValue.data(country ?? CountryService().getAll().first);
      }
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

  Future<void> selectCountry(String countryCode) async {
    final country = CountryService().findByCode(countryCode);
    if (country != null) {
      state = AsyncValue.data(country);
      await ref.read(countryManRepository).saveCountryMan(country.name);
    } else {
      state = AsyncValue.data(CountryService().getAll().first);
      await ref
          .read(countryManRepository)
          .saveCountryMan(CountryService().getAll().first.name);
    }
  }

  Future<void> clearSelection() async {
    await ref.read(countryManRepository).removeCountrySelection();
    state = AsyncValue.data(CountryService().getAll().first);
  }

  String getCountryName(String countryCode) {
    final country = CountryService().findByCode(countryCode);
    return country?.name ?? CountryService().getAll().first.name;
  }

  List<Country> getAllCountries() {
    return CountryService().getAll();
  }
}
