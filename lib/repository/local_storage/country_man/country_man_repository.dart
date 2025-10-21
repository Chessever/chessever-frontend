import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final countryManRepository = Provider((ref) => _CountryManRepository(ref));

class _CountryManRepository {
  _CountryManRepository(this.ref);

  final Ref ref;

  static String get countryName => 'selected_country_name';

  Future<void> saveCountryMan(String country) async {
    await ref.read(sharedPreferencesRepository).setString(countryName, country);
  }

  Future<void> removeCountrySelection() async {
    await ref.read(sharedPreferencesRepository).removeData(countryName);
  }

  Future<String?> getSavedCountryMan() async {
    return ref.read(sharedPreferencesRepository).getString(countryName);
  }
}
