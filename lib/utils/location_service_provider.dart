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
        // If the country code is not valid, try to map it using the mapper
        final mappedCode = CountryCodeMapper.mapToIsoCode(countryCode);
        if (mappedCode.isNotEmpty) {
          return mappedCode;
        }
      }
      print("Invalid One $countryCode");
      return '';
    } catch (error, _) {
      final code = CountryCodeMapper.mapToIsoCode(countryCode);
      if (code.isNotEmpty) {
        return code;
      }
      print("Invalid One $countryCode");
      return code;
    }
  }
}

class CountryCodeMapper {
  static const Map<String, String> _sportsToIsoMapping = {
    // UK constituents -> United Kingdom
    'ENG': 'GB', // England -> Great Britain
    'SCO': 'GB', // Scotland -> Great Britain
    'WLS': 'GB', // Wales -> Great Britain
    'NIR': 'GB', // Northern Ireland -> Great Britain
    // Common sports abbreviations -> ISO codes
    'GER': 'DE', // Germany
    'DEN': 'DK', // Denmark
    'NED': 'NL', // Netherlands
    'GRE': 'GR', // Greece
    'CRO': 'HR', // Croatia
    'RSA': 'ZA', // South Africa
    'NGR': 'NG', // Nigeria
    'SUI': 'CH', // Switzerland
    'CZE': 'CZ', // Czech Republic
    'SVK': 'SK', // Slovakia
    'SVN': 'SI', // Slovenia
    'AUT': 'AT', // Austria (this one is actually correct ISO-3)
    'BEL': 'BE', // Belgium (this one is actually correct ISO-3)
    'POR': 'PT', // Portugal
    'ESP': 'ES', // Spain
    'FRA': 'FR', // France
    'ITA': 'IT', // Italy
    'IRL': 'IE', // Ireland
    'POL': 'PL', // Poland
    'RUS': 'RU', // Russia
    'UKR': 'UA', // Ukraine
    'SWE': 'SE', // Sweden
    'NOR': 'NO', // Norway
    'FIN': 'FI', // Finland
    'ISL': 'IS', // Iceland
    'TUR': 'TR', // Turkey
    // Add more mappings as needed
    'IOM': 'IM', // Isle of Man
    'MAD': '', // Unknown - might be Madagascar (MG) or Madrid (not a country)
    'MGL': 'MN', // Mongolia (assuming MGL = Mongolia)
    'FID': '', // Unknown
    'CRC': 'CR', // Costa Rica (assuming CRC = Costa Rica)
    'LAT': 'LV', // Latvia (assuming LAT = Latvia)
    'VIE': '', // Vienna is a city, not a country
  };

  static String mapToIsoCode(String inputCode) {
    // First try direct mapping
    String mappedCode =
        _sportsToIsoMapping[inputCode.toUpperCase()] ?? inputCode;

    // If mapped to empty string, it's invalid
    if (mappedCode.isEmpty) {
      return '';
    }

    return mappedCode;
  }
}
