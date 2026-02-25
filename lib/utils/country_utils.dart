import 'package:country_picker/country_picker.dart';

class CountryUtils {
  /// Maps country_picker names to gamebase API-compatible country names.
  /// The gamebase API uses country names as shown on FIDE profiles.
  /// Note: The API uses ILIKE partial matching, so partial names work.
  static String toGamebaseCountryName(String countryPickerName) {
    // Map country_picker names to FIDE database names
    // Note: Database stores 'Türkiye' (with umlaut ü)
    const nameMapping = {
      'Turkey': 'Türkiye', // Database uses 'Türkiye' with umlaut
      'United States': 'United States of America',
      'Russia': 'Russia',
      'United Kingdom':
          'England', // FIDE uses England, Scotland, Wales separately
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

  /// Returns alternative country name variations for location search.
  /// Database locations use various formats - this ensures we match all of them.
  static List<String> getGamebaseCountryVariations(String countryName) {
    final primary = toGamebaseCountryName(countryName);

    // Map country names to all known variations in the database
    // These handle: accented characters, abbreviations, alternative names
    const variations = {
      // Turkey - database uses 'Türkiye' with umlaut (32 events)
      // 'Turkish' is safe with end-matching (won't match "Turkistan, Kazakhstan")
      'Turkey': ['Türkiye', 'Turkiye', 'Turkish'],
      'Türkiye': ['Turkey', 'Turkiye', 'Turkish'],

      // USA - database uses both 'USA' (37) and 'United States' (28)
      'United States': ['USA', 'United States of America'],
      'United States of America': ['USA', 'United States'],

      // UK - database uses 'England' (39), rarely 'United Kingdom' (9)
      'United Kingdom': ['England', 'UK', 'Britain'],
      'England': ['United Kingdom', 'UK'],

      // Mexico - database uses both 'México' (40) and 'Mexico' (35)
      'Mexico': ['México', 'Méx'],
      'México': ['Mexico'],

      // Czech - database uses both 'Czechia' (8) and 'Czech Republic' (3)
      'Czech Republic': ['Czechia', 'Czech'],
      'Czechia': ['Czech Republic', 'Czech'],

      // Peru - database sometimes uses 'Perú' with accent
      'Peru': ['Perú'],
      'Perú': ['Peru'],

      // Bahrain - database sometimes uses 'Bahréin' with accent
      'Bahrain': ['Bahréin'],
      'Bahréin': ['Bahrain'],

      // Venezuela - handle full name
      'Venezuela': ['Venezuela (Bolivarian Republic of)'],
      'Venezuela (Bolivarian Republic of)': ['Venezuela'],

      // Korea - handle both Koreas
      'South Korea': ['Korea'],
      'North Korea': ['Korea'],
      'Korea': ['South Korea'],
    };

    final result = <String>{primary};

    // Add variations for the original country name
    if (variations.containsKey(countryName)) {
      result.addAll(variations[countryName]!);
    }

    // Add variations for the mapped primary name (if different)
    if (primary != countryName && variations.containsKey(primary)) {
      result.addAll(variations[primary]!);
    }

    return result.toList();
  }

  /// Converts ISO 2-letter country code to FIDE 3-letter federation code.
  /// FIDE uses specific codes that differ from ISO 3166-1 alpha-3.
  /// Complete mapping based on all FIDE federations.
  static String toFideCode(String iso2Code) {
    const iso2ToFide = {
      // Major chess nations
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

      // Americas
      'AR': 'ARG',
      'BR': 'BRA',
      'PE': 'PER',
      'CU': 'CUB',
      'CA': 'CAN',
      'MX': 'MEX',
      'CO': 'COL',
      'CL': 'CHI',
      'VE': 'VEN',
      'EC': 'ECU',
      'UY': 'URU',
      'PY': 'PAR',
      'BO': 'BOL',
      'CR': 'CRC', // Costa Rica
      'PA': 'PAN', // Panama
      'GT': 'GUA', // Guatemala
      'SV': 'ESA', // El Salvador
      'HN': 'HON', // Honduras
      'NI': 'NCA', // Nicaragua
      'DO': 'DOM', // Dominican Republic
      'PR': 'PUR', // Puerto Rico
      'JM': 'JAM', // Jamaica
      'TT': 'TTO', // Trinidad and Tobago
      'BB': 'BAR', // Barbados
      'BS': 'BAH', // Bahamas
      'HT': 'HAI', // Haiti
      'SR': 'SUR', // Suriname
      'GY': 'GUY', // Guyana
      'AW': 'ARU', // Aruba
      'AN': 'AHO', // Netherlands Antilles (historical)
      'CW': 'AHO', // Curaçao (part of former Neth. Antilles)
      'SX': 'AHO', // Sint Maarten (part of former Neth. Antilles)
      'BQ': 'AHO', // Caribbean Netherlands
      'KY': 'CAY', // Cayman Islands
      'VI': 'ISV', // US Virgin Islands
      'AG': 'ANT', // Antigua and Barbuda
      'LC': 'LCA', // Saint Lucia
      'VC': 'VIN', // Saint Vincent
      'KN': 'SKN', // Saint Kitts and Nevis
      'DM': 'DMA', // Dominica
      'BM': 'BER', // Bermuda
      // Asia
      'VN': 'VIE',
      'PH': 'PHI',
      'ID': 'INA',
      'IR': 'IRI',
      'KR': 'KOR',
      'JP': 'JPN',
      'SG': 'SGP',
      'MY': 'MAS',
      'TH': 'THA',
      'PK': 'PAK',
      'BD': 'BAN',
      'LK': 'SRI',
      'NP': 'NEP',
      'HK': 'HKG', // Hong Kong
      'TW': 'TPE', // Chinese Taipei
      'MO': 'MAC', // Macau
      'MN': 'MGL', // Mongolia
      'UZ': 'UZB',
      'KZ': 'KAZ',
      'KG': 'KGZ', // Kyrgyzstan
      'TJ': 'TJK', // Tajikistan
      'TM': 'TKM', // Turkmenistan
      'AF': 'AFG', // Afghanistan
      'MM': 'MYA', // Myanmar
      'KH': 'CAM', // Cambodia
      'LA': 'LAO', // Laos
      'BT': 'BHU', // Bhutan
      'MV': 'MDV', // Maldives
      'BN': 'BRU', // Brunei
      'TL': 'TLS', // Timor-Leste
      // Middle East
      'SA': 'KSA',
      'AE': 'UAE',
      'QA': 'QAT',
      'IQ': 'IRQ', // Iraq
      'JO': 'JOR', // Jordan
      'LB': 'LBN', // Lebanon
      'SY': 'SYR', // Syria
      'YE': 'YEM', // Yemen
      'OM': 'OMA', // Oman
      'KW': 'KUW', // Kuwait
      'BH': 'BRN', // Bahrain
      'PS': 'PLE', // Palestine
      // Europe
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
      'IE': 'IRL',
      'IS': 'ISL',
      'BY': 'BLR', // Belarus
      'MD': 'MDA', // Moldova
      'ME': 'MNE', // Montenegro
      'AL': 'ALB', // Albania
      'XK': 'KOS', // Kosovo
      'CY': 'CYP', // Cyprus
      'MT': 'MLT', // Malta
      'LU': 'LUX', // Luxembourg
      'AD': 'AND', // Andorra
      'MC': 'MNC', // Monaco (FIDE uses MNC, not MON)
      'LI': 'LIE', // Liechtenstein
      'SM': 'SMR', // San Marino
      'FO': 'FAI', // Faroe Islands
      'JE': 'JCI', // Jersey
      'GG': 'GCI', // Guernsey
      'IM': 'IOM', // Isle of Man
      // Africa
      'ZA': 'RSA',
      'EG': 'EGY',
      'NG': 'NGR',
      'KE': 'KEN',
      'DZ': 'ALG', // Algeria
      'MA': 'MAR', // Morocco
      'TN': 'TUN', // Tunisia
      'LY': 'LBA', // Libya
      'SD': 'SUD', // Sudan
      'SS': 'SSD', // South Sudan
      'ET': 'ETH', // Ethiopia
      'UG': 'UGA', // Uganda
      'TZ': 'TAN', // Tanzania
      'RW': 'RWA', // Rwanda
      'BI': 'BDI', // Burundi
      'ZM': 'ZAM', // Zambia
      'ZW': 'ZIM', // Zimbabwe
      'BW': 'BOT', // Botswana
      'NA': 'NAM', // Namibia
      'AO': 'ANG', // Angola
      'MZ': 'MOZ', // Mozambique
      'MG': 'MAD', // Madagascar
      'MU': 'MRI', // Mauritius
      'SC': 'SEY', // Seychelles
      'MW': 'MAW', // Malawi
      'LS': 'LES', // Lesotho
      'SZ': 'SWZ', // Eswatini
      'CM': 'CMR', // Cameroon
      'CI': 'CIV', // Côte d'Ivoire
      'GH': 'GHA', // Ghana
      'SN': 'SEN', // Senegal
      'ML': 'MLI', // Mali
      'BF': 'BUR', // Burkina Faso
      'NE': 'NIG', // Niger
      'TD': 'CHA', // Chad
      'CF': 'CAF', // Central African Republic
      'GA': 'GAB', // Gabon
      'CG': 'CGO', // Congo
      'CD': 'COD', // DR Congo
      'GQ': 'GEQ', // Equatorial Guinea
      'ST': 'STP', // São Tomé and Príncipe
      'CV': 'CPV', // Cape Verde
      'GM': 'GAM', // Gambia
      'GW': 'GBS', // Guinea-Bissau
      'GN': 'GUI', // Guinea
      'SL': 'SLE', // Sierra Leone
      'LR': 'LBR', // Liberia
      'TG': 'TOG', // Togo
      'BJ': 'BEN', // Benin
      'MR': 'MTN', // Mauritania
      'DJ': 'DJI', // Djibouti
      'SO': 'SOM', // Somalia
      'ER': 'ERI', // Eritrea
      // Oceania
      'AU': 'AUS',
      'NZ': 'NZL',
      'FJ': 'FIJ', // Fiji
      'PG': 'PNG', // Papua New Guinea
      'GU': 'GUM', // Guam
      'PW': 'PLW', // Palau
      'NR': 'NRU', // Nauru
      'VU': 'VAN', // Vanuatu
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
  /// Complete mapping based on all FIDE federations.
  static String toIso2Code(String fideCode) {
    const fideToIso2 = {
      // Major chess nations
      'USA': 'US',
      'ENG': 'GB', // England (handled specially in FederationFlag)
      'SCO': 'GB', // Scotland (handled specially in FederationFlag)
      'WLS': 'GB', // Wales (handled specially in FederationFlag)
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

      // Americas
      'ARG': 'AR',
      'BRA': 'BR',
      'PER': 'PE',
      'CUB': 'CU',
      'CAN': 'CA',
      'MEX': 'MX',
      'COL': 'CO',
      'CHI': 'CL',
      'VEN': 'VE',
      'ECU': 'EC',
      'URU': 'UY',
      'PAR': 'PY',
      'BOL': 'BO',
      'CRC': 'CR', // Costa Rica
      'PAN': 'PA', // Panama
      'GUA': 'GT', // Guatemala
      'ESA': 'SV', // El Salvador
      'HON': 'HN', // Honduras
      'NCA': 'NI', // Nicaragua
      'DOM': 'DO', // Dominican Republic
      'PUR': 'PR', // Puerto Rico
      'JAM': 'JM', // Jamaica
      'TTO': 'TT', // Trinidad and Tobago
      'BAR': 'BB', // Barbados
      'BAH': 'BS', // Bahamas
      'HAI': 'HT', // Haiti
      'SUR': 'SR', // Suriname
      'GUY': 'GY', // Guyana
      'ARU': 'AW', // Aruba
      'AHO': 'CW', // Netherlands Antilles (now Curaçao)
      'CAY': 'KY', // Cayman Islands
      'ISV': 'VI', // US Virgin Islands
      'ANT': 'AG', // Antigua and Barbuda
      'LCA': 'LC', // Saint Lucia
      'VIN': 'VC', // Saint Vincent
      'SKN': 'KN', // Saint Kitts and Nevis
      'DMA': 'DM', // Dominica
      'BER': 'BM', // Bermuda
      // Asia
      'VIE': 'VN',
      'PHI': 'PH',
      'INA': 'ID',
      'IRI': 'IR',
      'KOR': 'KR',
      'JPN': 'JP',
      'SGP': 'SG',
      'MAS': 'MY',
      'THA': 'TH',
      'PAK': 'PK',
      'BAN': 'BD',
      'SRI': 'LK',
      'NEP': 'NP',
      'HKG': 'HK', // Hong Kong
      'TPE': 'TW', // Chinese Taipei
      'MAC': 'MO', // Macau
      'MGL': 'MN', // Mongolia
      'UZB': 'UZ',
      'KAZ': 'KZ',
      'KGZ': 'KG', // Kyrgyzstan
      'TJK': 'TJ', // Tajikistan
      'TKM': 'TM', // Turkmenistan
      'AFG': 'AF', // Afghanistan
      'MYA': 'MM', // Myanmar
      'CAM': 'KH', // Cambodia
      'LAO': 'LA', // Laos
      'BHU': 'BT', // Bhutan
      'MDV': 'MV', // Maldives
      'BRU': 'BN', // Brunei
      'TLS': 'TL', // Timor-Leste
      // Middle East
      'KSA': 'SA',
      'UAE': 'AE',
      'QAT': 'QA',
      'IRQ': 'IQ', // Iraq
      'JOR': 'JO', // Jordan
      'LBN': 'LB', // Lebanon
      'SYR': 'SY', // Syria
      'YEM': 'YE', // Yemen
      'OMA': 'OM', // Oman
      'KUW': 'KW', // Kuwait
      'BRN': 'BH', // Bahrain
      'PLE': 'PS', // Palestine
      // Europe
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
      'IRL': 'IE',
      'ISL': 'IS',
      'BLR': 'BY', // Belarus
      'MDA': 'MD', // Moldova
      'MNE': 'ME', // Montenegro
      'ALB': 'AL', // Albania
      'KOS': 'XK', // Kosovo
      'CYP': 'CY', // Cyprus
      'MLT': 'MT', // Malta
      'LUX': 'LU', // Luxembourg
      'AND': 'AD', // Andorra
      'MNC': 'MC', // Monaco
      'MON': 'MC', // Monaco (alternate)
      'LIE': 'LI', // Liechtenstein
      'SMR': 'SM', // San Marino
      'FAI': 'FO', // Faroe Islands
      'JCI': 'JE', // Jersey
      'GCI': 'GG', // Guernsey
      'IOM': 'IM', // Isle of Man
      // Africa
      'RSA': 'ZA',
      'EGY': 'EG',
      'NGR': 'NG',
      'KEN': 'KE',
      'ALG': 'DZ', // Algeria
      'MAR': 'MA', // Morocco
      'TUN': 'TN', // Tunisia
      'LBA': 'LY', // Libya
      'SUD': 'SD', // Sudan
      'SSD': 'SS', // South Sudan
      'ETH': 'ET', // Ethiopia
      'UGA': 'UG', // Uganda
      'TAN': 'TZ', // Tanzania
      'RWA': 'RW', // Rwanda
      'BDI': 'BI', // Burundi
      'ZAM': 'ZM', // Zambia
      'ZIM': 'ZW', // Zimbabwe
      'BOT': 'BW', // Botswana
      'NAM': 'NA', // Namibia
      'ANG': 'AO', // Angola
      'MOZ': 'MZ', // Mozambique
      'MAD': 'MG', // Madagascar
      'MRI': 'MU', // Mauritius
      'SEY': 'SC', // Seychelles
      'MAW': 'MW', // Malawi
      'LES': 'LS', // Lesotho
      'SWZ': 'SZ', // Eswatini
      'CMR': 'CM', // Cameroon
      'CIV': 'CI', // Côte d'Ivoire
      'GHA': 'GH', // Ghana
      'SEN': 'SN', // Senegal
      'MLI': 'ML', // Mali
      'BUR': 'BF', // Burkina Faso
      'NIG': 'NE', // Niger
      'CHA': 'TD', // Chad
      'CAF': 'CF', // Central African Republic
      'GAB': 'GA', // Gabon
      'CGO': 'CG', // Congo
      'COD': 'CD', // DR Congo
      'GEQ': 'GQ', // Equatorial Guinea
      'STP': 'ST', // São Tomé and Príncipe
      'CPV': 'CV', // Cape Verde
      'GAM': 'GM', // Gambia
      'GBS': 'GW', // Guinea-Bissau
      'GUI': 'GN', // Guinea
      'SLE': 'SL', // Sierra Leone
      'LBR': 'LR', // Liberia
      'TOG': 'TG', // Togo
      'BEN': 'BJ', // Benin
      'MTN': 'MR', // Mauritania
      'DJI': 'DJ', // Djibouti
      'SOM': 'SO', // Somalia
      'ERI': 'ER', // Eritrea
      // Oceania
      'AUS': 'AU',
      'NZL': 'NZ',
      'FIJ': 'FJ', // Fiji
      'PNG': 'PG', // Papua New Guinea
      'GUM': 'GU', // Guam
      'PLW': 'PW', // Palau
      'NRU': 'NR', // Nauru
      'VAN': 'VU', // Vanuatu
      // Special
      'FID': 'XX', // FIDE (no country)
      'NON': 'XX', // No nation
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

  /// Converts a FIDE 3-letter federation code to a flag emoji.
  /// Returns the flag emoji or empty string if not found.
  static String toFlagEmoji(String fideCode) {
    if (fideCode.isEmpty) return '';

    // Convert FIDE code to ISO 2-letter code first
    final iso2 = toIso2Code(fideCode);
    if (iso2.length != 2) return '';

    // Countries that should not show flags (sanctions/restrictions)
    const restrictedCountries = {'RU', 'BY'};
    if (restrictedCountries.contains(iso2.toUpperCase())) return '';

    // Convert ISO 2-letter code to flag emoji
    // Each letter is converted to its regional indicator symbol
    final upper = iso2.toUpperCase();
    final flag = String.fromCharCodes(
      upper.codeUnits.map((c) => c - 0x41 + 0x1F1E6),
    );
    return flag;
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
