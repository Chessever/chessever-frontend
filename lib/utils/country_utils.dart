import 'package:country_picker/country_picker.dart';

class CountryUtils {
  static String? getCountryCode(String? location) {
    if (location == null || location.isEmpty) return null;

    // Try to match by name
    final country = CountryService().findByName(location);
    if (country != null) return country.countryCode;

    // Try to match by code directly (if location is just "US")
    final countryByCode = CountryService().findByCode(location);
    if (countryByCode != null) return countryByCode.countryCode;

    // Try to find country in a longer string (e.g. "Baku, Azerbaijan")
    final parts = location.split(',');
    for (final part in parts) {
      final trimmed = part.trim();
      final c = CountryService().findByName(trimmed);
      if (c != null) return c.countryCode;
    }

    return null;
  }
}
