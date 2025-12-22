import 'package:country_picker/country_picker.dart';

class CountryUtils {
  /// Maps country_picker names to gamebase API-compatible country names.
  /// The gamebase API uses country names as shown on FIDE profiles.
  /// Note: The API uses ILIKE partial matching, so partial names work.
  static String toGamebaseCountryName(String countryPickerName) {
    // Map country_picker names to FIDE database names
    // Note: Database stores 'Turkiye' (no umlaut), not 'Türkiye'
    const nameMapping = {
      'Turkey': 'Turkiye', // Database uses 'Turkiye' without umlaut
      'United States': 'United States of America',
      'Russia': 'Russia',
      'United Kingdom': 'England', // FIDE uses England, Scotland, Wales separately
      'South Korea': 'Korea',
      'North Korea': 'Korea',
      'Czech Republic': 'Czech Republic', // Database uses 'Czech Republic'
      'Czechia': 'Czech Republic',
      'Iran, Islamic Republic Of': 'Iran',
      'Venezuela (Bolivarian Republic of)': 'Venezuela',
      'Bolivia (Plurinational State of)': 'Bolivia',
      'Moldova (Republic of)': 'Moldova',
      'Macedonia (the former Yugoslav Republic of)': 'North Macedonia',
      'North Macedonia': 'North Macedonia',
      'Taiwan': 'Chinese Taipei',
      'Vietnam': 'Vietnam',
      'Viet Nam': 'Vietnam',
      'Ivory Coast': 'Cote d\'Ivoire',
      "Côte d'Ivoire": 'Cote d\'Ivoire',
    };

    return nameMapping[countryPickerName] ?? countryPickerName;
  }

  /// Returns alternative country name variations for gamebase API search.
  /// The API uses ILIKE partial matching, so we only need one good variation.
  /// The primary variation from toGamebaseCountryName() should work in most cases.
  static List<String> getGamebaseCountryVariations(String countryName) {
    final primary = toGamebaseCountryName(countryName);

    // Only add variations if the primary might not match
    // Note: API uses ILIKE '%value%' so partial names work
    // e.g., 'Turk' matches 'Turkiye', 'United' matches 'United States of America'
    const variations = {
      'United States of America': ['United'], // 'United' partial matches
      'United Kingdom': ['England'], // UK games are under England
      'Turkey': ['Turkiye'], // Ensure we try the database value
      'Turkiye': ['Turk'], // Partial match fallback
    };

    final result = <String>[primary];
    if (variations.containsKey(countryName)) {
      result.addAll(variations[countryName]!);
    }
    if (variations.containsKey(primary) && primary != countryName) {
      result.addAll(variations[primary]!);
    }

    return result.toSet().toList(); // Remove duplicates
  }

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

  /// Converts FIDE country name (e.g., "Norway", "Turkiye") to ISO 2-letter code.
  /// Used for displaying flags when we have the full country name from Gamebase API.
  static String countryNameToIso2(String countryName) {
    const nameToIso2 = {
      'norway': 'NO',
      'turkiye': 'TR',
      'turkey': 'TR',
      'russia': 'RU',
      'united states of america': 'US',
      'united states': 'US',
      'england': 'GB',
      'scotland': 'GB',
      'wales': 'GB',
      'germany': 'DE',
      'france': 'FR',
      'spain': 'ES',
      'italy': 'IT',
      'netherlands': 'NL',
      'poland': 'PL',
      'czech republic': 'CZ',
      'czechia': 'CZ',
      'hungary': 'HU',
      'romania': 'RO',
      'ukraine': 'UA',
      'azerbaijan': 'AZ',
      'armenia': 'AM',
      'georgia': 'GE',
      'israel': 'IL',
      'argentina': 'AR',
      'brazil': 'BR',
      'peru': 'PE',
      'cuba': 'CU',
      'vietnam': 'VN',
      'philippines': 'PH',
      'indonesia': 'ID',
      'iran': 'IR',
      'sweden': 'SE',
      'denmark': 'DK',
      'finland': 'FI',
      'austria': 'AT',
      'switzerland': 'CH',
      'belgium': 'BE',
      'portugal': 'PT',
      'greece': 'GR',
      'serbia': 'RS',
      'croatia': 'HR',
      'slovenia': 'SI',
      'slovakia': 'SK',
      'bulgaria': 'BG',
      'north macedonia': 'MK',
      'bosnia and herzegovina': 'BA',
      'estonia': 'EE',
      'latvia': 'LV',
      'lithuania': 'LT',
      'australia': 'AU',
      'new zealand': 'NZ',
      'south africa': 'ZA',
      'egypt': 'EG',
      'nigeria': 'NG',
      'kenya': 'KE',
      'uzbekistan': 'UZ',
      'kazakhstan': 'KZ',
      'mongolia': 'MN',
      'korea': 'KR',
      'japan': 'JP',
      'singapore': 'SG',
      'malaysia': 'MY',
      'thailand': 'TH',
      'pakistan': 'PK',
      'bangladesh': 'BD',
      'sri lanka': 'LK',
      'nepal': 'NP',
      'saudi arabia': 'SA',
      'united arab emirates': 'AE',
      'qatar': 'QA',
      'canada': 'CA',
      'mexico': 'MX',
      'colombia': 'CO',
      'chile': 'CL',
      'venezuela': 'VE',
      'ecuador': 'EC',
      'uruguay': 'UY',
      'paraguay': 'PY',
      'bolivia': 'BO',
      'ireland': 'IE',
      'iceland': 'IS',
      'india': 'IN',
      'china': 'CN',
      'chinese taipei': 'TW',
      'belarus': 'BY',
      'moldova': 'MD',
      'albania': 'AL',
      'montenegro': 'ME',
      'cyprus': 'CY',
      'malta': 'MT',
      'luxembourg': 'LU',
      'andorra': 'AD',
      'monaco': 'MC',
      'liechtenstein': 'LI',
    };

    final lower = countryName.toLowerCase().trim();
    return nameToIso2[lower] ?? '';
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

  /// Gets the country name from a FIDE 3-letter federation code.
  /// Returns the full country name or empty string if not found.
  static String getCountryName(String fideCode) {
    const fideToCountryName = {
      'USA': 'United States',
      'ENG': 'England',
      'SCO': 'Scotland',
      'WLS': 'Wales',
      'RUS': 'Russia',
      'CHN': 'China',
      'IND': 'India',
      'GER': 'Germany',
      'FRA': 'France',
      'ESP': 'Spain',
      'ITA': 'Italy',
      'NED': 'Netherlands',
      'POL': 'Poland',
      'CZE': 'Czech Republic',
      'HUN': 'Hungary',
      'ROU': 'Romania',
      'UKR': 'Ukraine',
      'AZE': 'Azerbaijan',
      'ARM': 'Armenia',
      'GEO': 'Georgia',
      'TUR': 'Turkey',
      'ISR': 'Israel',
      'ARG': 'Argentina',
      'BRA': 'Brazil',
      'PER': 'Peru',
      'CUB': 'Cuba',
      'VIE': 'Vietnam',
      'PHI': 'Philippines',
      'INA': 'Indonesia',
      'IRI': 'Iran',
      'NOR': 'Norway',
      'SWE': 'Sweden',
      'DEN': 'Denmark',
      'FIN': 'Finland',
      'AUT': 'Austria',
      'SUI': 'Switzerland',
      'BEL': 'Belgium',
      'POR': 'Portugal',
      'GRE': 'Greece',
      'SRB': 'Serbia',
      'CRO': 'Croatia',
      'SLO': 'Slovenia',
      'SVK': 'Slovakia',
      'BUL': 'Bulgaria',
      'MKD': 'North Macedonia',
      'BIH': 'Bosnia',
      'EST': 'Estonia',
      'LAT': 'Latvia',
      'LTU': 'Lithuania',
      'AUS': 'Australia',
      'NZL': 'New Zealand',
      'RSA': 'South Africa',
      'EGY': 'Egypt',
      'NGR': 'Nigeria',
      'KEN': 'Kenya',
      'UZB': 'Uzbekistan',
      'KAZ': 'Kazakhstan',
      'MGL': 'Mongolia',
      'KOR': 'South Korea',
      'JPN': 'Japan',
      'SGP': 'Singapore',
      'MAS': 'Malaysia',
      'THA': 'Thailand',
      'PAK': 'Pakistan',
      'BAN': 'Bangladesh',
      'SRI': 'Sri Lanka',
      'NEP': 'Nepal',
      'KSA': 'Saudi Arabia',
      'UAE': 'United Arab Emirates',
      'QAT': 'Qatar',
      'CAN': 'Canada',
      'MEX': 'Mexico',
      'COL': 'Colombia',
      'CHI': 'Chile',
      'VEN': 'Venezuela',
      'ECU': 'Ecuador',
      'URU': 'Uruguay',
      'PAR': 'Paraguay',
      'BOL': 'Bolivia',
      'IRL': 'Ireland',
      'ISL': 'Iceland',
      'BLR': 'Belarus',
      'MDA': 'Moldova',
      'ALB': 'Albania',
      'MNE': 'Montenegro',
      'CYP': 'Cyprus',
      'MLT': 'Malta',
      'LUX': 'Luxembourg',
      'AND': 'Andorra',
      'MON': 'Monaco',
      'LIE': 'Liechtenstein',
      'SMR': 'San Marino',
      'FAI': 'Faroe Islands',
    };

    final upper = fideCode.toUpperCase();
    return fideToCountryName[upper] ?? '';
  }
}
