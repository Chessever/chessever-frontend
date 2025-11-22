import 'package:country_picker/country_picker.dart';

class CountryUtils {
  /// Converts ISO 2-letter country code to FIDE 3-letter federation code.
  /// FIDE uses specific codes that differ from ISO 3166-1 alpha-3.
  static String toFideCode(String iso2Code) {
    const iso2ToFide = {
      'US': 'USA',
      'GB': 'ENG', // UK defaults to England in FIDE
      'RU': 'RUS',
      'CN': 'CHN',
      'IN': 'IND',
      'DE': 'GER',
      'FR': 'FRA',
      'ES': 'ESP',
      'IT': 'ITA',
      'NL': 'NED',
      'PL': 'POL',
      'CZ': 'CZE',
      'HU': 'HUN',
      'RO': 'ROU',
      'UA': 'UKR',
      'AZ': 'AZE',
      'AM': 'ARM',
      'GE': 'GEO',
      'TR': 'TUR',
      'IL': 'ISR',
      'AR': 'ARG',
      'BR': 'BRA',
      'PE': 'PER',
      'CU': 'CUB',
      'VN': 'VIE',
      'PH': 'PHI',
      'ID': 'INA',
      'IR': 'IRI',
      'NO': 'NOR',
      'SE': 'SWE',
      'DK': 'DEN',
      'FI': 'FIN',
      'AT': 'AUT',
      'CH': 'SUI',
      'BE': 'BEL',
      'PT': 'POR',
      'GR': 'GRE',
      'RS': 'SRB',
      'HR': 'CRO',
      'SI': 'SLO',
      'SK': 'SVK',
      'BG': 'BUL',
      'MK': 'MKD',
      'BA': 'BIH',
      'EE': 'EST',
      'LV': 'LAT',
      'LT': 'LTU',
      'AU': 'AUS',
      'NZ': 'NZL',
      'ZA': 'RSA',
      'EG': 'EGY',
      'NG': 'NGR',
      'KE': 'KEN',
      'UZ': 'UZB',
      'KZ': 'KAZ',
      'MN': 'MGL',
      'KR': 'KOR',
      'JP': 'JPN',
      'SG': 'SGP',
      'MY': 'MAS',
      'TH': 'THA',
      'PK': 'PAK',
      'BD': 'BAN',
      'LK': 'SRI',
      'NP': 'NEP',
      'SA': 'KSA',
      'AE': 'UAE',
      'QA': 'QAT',
      'CA': 'CAN',
      'MX': 'MEX',
      'CO': 'COL',
      'CL': 'CHI',
      'VE': 'VEN',
      'EC': 'ECU',
      'UY': 'URU',
      'PY': 'PAR',
      'BO': 'BOL',
      'IE': 'IRL',
      'IS': 'ISL',
    };

    final upper = iso2Code.toUpperCase();
    return iso2ToFide[upper] ?? upper;
  }

  /// Converts FIDE 3-letter federation code to ISO 2-letter country code.
  /// Used for displaying flags (CountryFlag expects ISO 2-letter codes).
  static String toIso2Code(String fideCode) {
    const fideToIso2 = {
      'USA': 'US',
      'ENG': 'GB',
      'SCO': 'GB', // Scotland
      'WLS': 'GB', // Wales
      'RUS': 'RU',
      'CHN': 'CN',
      'IND': 'IN',
      'GER': 'DE',
      'FRA': 'FR',
      'ESP': 'ES',
      'ITA': 'IT',
      'NED': 'NL',
      'POL': 'PL',
      'CZE': 'CZ',
      'HUN': 'HU',
      'ROU': 'RO',
      'UKR': 'UA',
      'AZE': 'AZ',
      'ARM': 'AM',
      'GEO': 'GE',
      'TUR': 'TR',
      'ISR': 'IL',
      'ARG': 'AR',
      'BRA': 'BR',
      'PER': 'PE',
      'CUB': 'CU',
      'VIE': 'VN',
      'PHI': 'PH',
      'INA': 'ID',
      'IRI': 'IR',
      'NOR': 'NO',
      'SWE': 'SE',
      'DEN': 'DK',
      'FIN': 'FI',
      'AUT': 'AT',
      'SUI': 'CH',
      'BEL': 'BE',
      'POR': 'PT',
      'GRE': 'GR',
      'SRB': 'RS',
      'CRO': 'HR',
      'SLO': 'SI',
      'SVK': 'SK',
      'BUL': 'BG',
      'MKD': 'MK',
      'BIH': 'BA',
      'EST': 'EE',
      'LAT': 'LV',
      'LTU': 'LT',
      'AUS': 'AU',
      'NZL': 'NZ',
      'RSA': 'ZA',
      'EGY': 'EG',
      'NGR': 'NG',
      'KEN': 'KE',
      'UZB': 'UZ',
      'KAZ': 'KZ',
      'MGL': 'MN',
      'KOR': 'KR',
      'JPN': 'JP',
      'SGP': 'SG',
      'MAS': 'MY',
      'THA': 'TH',
      'PAK': 'PK',
      'BAN': 'BD',
      'SRI': 'LK',
      'NEP': 'NP',
      'KSA': 'SA',
      'UAE': 'AE',
      'QAT': 'QA',
      'CAN': 'CA',
      'MEX': 'MX',
      'COL': 'CO',
      'CHI': 'CL',
      'VEN': 'VE',
      'ECU': 'EC',
      'URU': 'UY',
      'PAR': 'PY',
      'BOL': 'BO',
      'IRL': 'IE',
      'ISL': 'IS',
      'BLR': 'BY', // Belarus
      'MDA': 'MD', // Moldova
      'ALB': 'AL', // Albania
      'MNE': 'ME', // Montenegro
      'CYP': 'CY', // Cyprus
      'MLT': 'MT', // Malta
      'LUX': 'LU', // Luxembourg
      'AND': 'AD', // Andorra
      'MON': 'MC', // Monaco
      'LIE': 'LI', // Liechtenstein
      'SMR': 'SM', // San Marino
      'FAI': 'FO', // Faroe Islands
      'FID': 'FI', // FIDE (fallback to something)
    };

    final upper = fideCode.toUpperCase();
    return fideToIso2[upper] ?? upper;
  }

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
