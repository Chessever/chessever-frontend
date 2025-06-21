import 'package:country_picker/country_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final countryDropdownProvider =
    StateNotifierProvider<SelectedCountryNotifier, AsyncValue<Country>>(
      (ref) => SelectedCountryNotifier(),
    );

class SelectedCountryNotifier extends StateNotifier<AsyncValue<Country>> {
  SelectedCountryNotifier() : super(AsyncValue.loading());

  void selectCountry(String countryCode) {
    final country = CountryService().findByCode(countryCode);
    state = AsyncValue.data(country ?? CountryService().getAll().first);
  }

  void clearSelection() {
    state = AsyncValue.data(CountryService().getAll().first);
  }

  String getCountryName(String countryCode){
    final country = CountryService().findByCode(countryCode);
    return country?.name ?? CountryService().getAll().first.name;
  }

  List<Country> getAllCountries(){
    return CountryService().getAll();
  }
}
