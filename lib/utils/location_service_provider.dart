import 'package:country_code/country_code.dart';
import 'package:country_picker/country_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final locationServiceProvider = AutoDisposeProvider<LocationService>((ref) {
  return LocationService();
});

class LocationService {
  String getCountryCode(String location) {
    try {
      // Extract country name from location (assuming it's the last part after comma)
      String countryName = location.split(',').last.trim();

      Country country = Country.parse(countryName);

      return country.countryCode;
    } catch (error, _) {
      return '';
    }
  }

  String getCountryName(String location) {
    try {
      // Extract country name from location (assuming it's the last part after comma)
      String countryName = location.split(',').last.trim();

      Country country = Country.parse(countryName);

      return country.name;
    } catch (error, _) {
      return '';
    }
  }

  String getValidCountryCode(String countryCode) {
    try {
      var code = CountryCode.tryParse(countryCode);
      if (code != null) {
        return code.alpha2;
      } else {
        return '';
      }
    } catch (error, _) {
      return '';
    }
  }
}
