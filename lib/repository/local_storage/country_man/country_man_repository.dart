import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final countryManRepository = Provider((ref) => _CountryManRepository(ref));

class _CountryManRepository {
  _CountryManRepository(this.ref);

  final Ref ref;

  Future<void> saveCountryMan(String countryName) async {
    await ref
        .read(sharedPreferencesRepository)
        .setString('selected_country_name', countryName);
  }

  Future<String?> getSavedCountryMan() async {
    return ref
        .read(sharedPreferencesRepository)
        .getString('selected_country_name');
  }
}
