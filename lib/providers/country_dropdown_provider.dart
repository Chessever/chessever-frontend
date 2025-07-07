import 'package:chessever2/repository/local_storage/country_man/country_man_repository.dart';
import 'package:country_picker/country_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final countryDropdownProvider =
    StateNotifierProvider<SelectedCountryNotifier, AsyncValue<Country>>(
      (ref) => SelectedCountryNotifier(ref),
    );

class SelectedCountryNotifier extends StateNotifier<AsyncValue<Country>> {
  SelectedCountryNotifier(this.ref) : super(AsyncValue.loading());

  final Ref ref;

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

  void clearSelection() {
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
