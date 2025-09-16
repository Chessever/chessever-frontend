import 'package:country_code/country_code.dart';
import 'package:country_picker/country_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final locationServiceProvider = AutoDisposeProvider<LocationService>((ref) {
  return LocationService();
});

class LocationService {
  static const Map<String, String> _federationToCountryCodeMap = {
    // Chess federation codes to ISO country codes mapping
    'GER': 'DE',
    'USA': 'US',
    'RUS': 'RU',
    'CHN': 'CN',
    'FRA': 'FR',
    'ITA': 'IT',
    'ESP': 'ES',
    'NED': 'NL',
    'POL': 'PL',
    'UKR': 'UA',
    'CZE': 'CZ',
    'HUN': 'HU',
    'SVK': 'SK',
    'SUI': 'CH',
    'AUT': 'AT',
    'BEL': 'BE',
    'DEN': 'DK',
    'SWE': 'SE',
    'NOR': 'NO',
    'FIN': 'FI',
    'GRE': 'GR',
    'POR': 'PT',
    'CRO': 'HR',
    'SLO': 'SI',
    'BIH': 'BA',
    'SRB': 'RS',
    'MNE': 'ME',
    'MKD': 'MK',
    'BUL': 'BG',
    'ROU': 'RO',
    'MDA': 'MD',
    'LTU': 'LT',
    'LAT': 'LV',
    'EST': 'EE',
    'BLR': 'BY',
    'GEO': 'GE',
    'ARM': 'AM',
    'AZE': 'AZ',
    'TUR': 'TR',
    'ISR': 'IL',
    'JPN': 'JP',
    'KOR': 'KR',
    'IND': 'IN',
    'AUS': 'AU',
    'NZL': 'NZ',
    'CAN': 'CA',
    'BRA': 'BR',
    'ARG': 'AR',
    'CHI': 'CL',
    'COL': 'CO',
    'PER': 'PE',
    'VEN': 'VE',
    'URU': 'UY',
    'PAR': 'PY',
    'BOL': 'BO',
    'ECU': 'EC',
    'GUA': 'GT',
    'MEX': 'MX',
    'CUB': 'CU',
    'DOM': 'DO',
    'PUR': 'PR',
    'JAM': 'JM',
    'BAR': 'BB',
    'TTO': 'TT',
    'EGY': 'EG',
    'RSA': 'ZA',
    'MAR': 'MA',
    'TUN': 'TN',
    'ALG': 'DZ',
    'LBA': 'LY',
    'SUD': 'SD',
    'ETH': 'ET',
    'KEN': 'KE',
    'UGA': 'UG',
    'TAN': 'TZ',
    'ZAM': 'ZM',
    'ZIM': 'ZW',
    'BOT': 'BW',
    'NAM': 'NA',
    'ANG': 'AO',
    'MOZ': 'MZ',
    'MAD': 'MG',
    'MRI': 'MU',
    'SEY': 'SC',
    'GHA': 'GH',
    'NGR': 'NG',
    'SEN': 'SN',
    'CIV': 'CI',
    'CMR': 'CM',  // Cameroon
    'GAB': 'GA',
    'CGO': 'CG',
    'CAF': 'CF',
    'CHD': 'TD',
    'BUR': 'BF',
    'MLI': 'ML',
    'NIG': 'NE',
    'BEN': 'BJ',
    'TOG': 'TG',
    'SLE': 'SL',
    'LBR': 'LR',
    'GUI': 'GN',
    'GBS': 'GW',
    'CPV': 'CV',
    'GAM': 'GM',
    'MTN': 'MR',
    'IRQ': 'IQ',
    'IRI': 'IR',  // Iran (Islamic Republic of Iran)
    'IRN': 'IR',  // Iran (alternative code)
    'KSA': 'SA',
    'UAE': 'AE',
    'QAT': 'QA',
    'KUW': 'KW',
    'BRN': 'BH',
    'OMA': 'OM',
    'YEM': 'YE',
    'JOR': 'JO',
    'LBN': 'LB',
    'SYR': 'SY',
    'PAL': 'PS',
    'AFG': 'AF',
    'PAK': 'PK',
    'BAN': 'BD',
    'SRI': 'LK',
    'NEP': 'NP',
    'BHU': 'BT',
    'MGL': 'MN',
    'UZB': 'UZ',
    'KAZ': 'KZ',
    'KGZ': 'KG',
    'TJK': 'TJ',
    'TKM': 'TM',
    'VIE': 'VN',
    'THA': 'TH',
    'MAS': 'MY',
    'SIN': 'SG',
    'PHI': 'PH',
    'INA': 'ID',
    'BRU': 'BN',
    'KHM': 'KH',  // Cambodia
    'LAO': 'LA',
    'MYA': 'MM',
    'HKG': 'HK',
    'MAC': 'MO',
    'TPE': 'TW',
    'PNG': 'PG',
    'SOL': 'SB',
    'VAN': 'VU',
    'NCL': 'NC',
    'GUM': 'GU',
    'SAM': 'WS',
    'COK': 'CK',
    'TGA': 'TO',
    'KIR': 'KI',
    'TUV': 'TV',
    'NAU': 'NR',
    'PLW': 'PW',
    'MHL': 'MH',
    'FSM': 'FM',
    'ISL': 'IS',
    'FAI': 'FO',
    'LIE': 'LI',
    'MON': 'MC',
    'SMR': 'SM',
    'VAT': 'VA',
    'MLT': 'MT',
    'CYP': 'CY',
    'LUX': 'LU',
    'AND': 'AD',
    'IRL': 'IE',
    'GBR': 'GB',
    'ENG': 'GB',
    'SCO': 'GB',
    'WLS': 'GB',
    'NIR': 'GB',
  };

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
    if (countryCode.isEmpty) return '';
    
    // First try direct ISO country code parsing
    try {
      var code = CountryCode.tryParse(countryCode);
      if (code != null) {
        return code.alpha2;
      }
    } catch (_) {
      // Continue to federation mapping
    }
    
    // Try federation code mapping
    String? mappedCode = _federationToCountryCodeMap[countryCode.toUpperCase()];
    if (mappedCode != null) {
      return mappedCode;
    }
    
    // Last fallback: try 3-letter to 2-letter conversion for common cases
    if (countryCode.length == 3) {
      try {
        var code = CountryCode.tryParse(countryCode);
        if (code != null) {
          return code.alpha2;
        }
      } catch (_) {
        // If still fails, return empty
      }
    }
    
    return '';
  }
}
