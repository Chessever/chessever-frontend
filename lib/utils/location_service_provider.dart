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
    'CMR': 'CM', // Cameroon
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
    'IRI': 'IR', // Iran (Islamic Republic of Iran)
    'IRN': 'IR', // Iran (alternative code)
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
    'KHM': 'KH', // Cambodia
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

  // Online platform hosts that appear in `tours.info.location` for online
  // events (e.g. "Chess.com", "lichess.org", "tcec-chess.com"). Tournaments
  // played on these platforms have no physical city, so the Location row
  // should switch to a globe + "Online" label rather than show a fake flag.
  static const Set<String> _onlinePlatformHosts = {
    'chess.com',
    'lichess.org',
    'lichess',
    'tcec-chess.com',
    'tcec',
    'chess24.com',
    'chess24',
    'chessbase.com',
    'playchess.com',
    'iccf.com',
  };

  /// Whether `location` should be rendered as an online platform rather
  /// than a physical place.
  ///
  /// Detected when the value matches a known platform host or looks like a
  /// bare URL/domain (no comma, no spaces, contains a dot).
  bool isOnlinePlatform(String location) {
    final raw = location.trim().toLowerCase();
    if (raw.isEmpty) return false;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return true;
    final host = _stripUrl(raw);
    if (_onlinePlatformHosts.contains(host)) return true;
    return !host.contains(',') && !host.contains(' ') && host.contains('.');
  }

  /// Returns a display-friendly platform name for `location`, e.g.
  /// "Chess.com" → "Chess.com", "lichess.org" → "Lichess",
  /// "https://lichess.org/broadcast/foo" → "Lichess".
  String prettifyPlatformName(String location) {
    final host = _stripUrl(location.trim().toLowerCase());
    if (host.contains('chess.com')) return 'Chess.com';
    if (host.contains('lichess')) return 'Lichess';
    if (host.contains('tcec')) return 'TCEC';
    if (host.contains('chess24')) return 'Chess24';
    if (host.contains('chessbase')) return 'ChessBase';
    if (host.contains('playchess')) return 'Playchess';
    if (host.contains('iccf')) return 'ICCF';
    return host.isEmpty ? location.trim() : host;
  }

  String _stripUrl(String value) {
    var s = value.replaceFirst(RegExp(r'^https?://'), '');
    s = s.split('/').first;
    if (s.startsWith('www.')) s = s.substring(4);
    return s;
  }

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

    // Try 3-letter to 2-letter conversion for common cases
    if (countryCode.length == 3) {
      try {
        var code = CountryCode.tryParse(countryCode);
        if (code != null) {
          return code.alpha2;
        }
      } catch (_) {
        // Continue to name-based fallback
      }
    }

    // Fallback: if input looks like a full country name (e.g., "Azerbaijan"),
    // try name-based lookup. Gamebase returns country names, not codes.
    if (countryCode.length > 3) {
      return getValidCountryCodeFromName(countryCode);
    }

    return '';
  }

  String getValidCountryCodeFromName(String name) {
    if (name.trim().isEmpty) return '';

    try {
      // Normalize input
      final normalizedName = name.trim().toLowerCase();

      // Try using the `country_picker` package
      final allCountries = CountryService().getAll();
      final match = allCountries.firstWhere(
        (c) =>
            c.name.toLowerCase() == normalizedName ||
            c.displayNameNoCountryCode.toLowerCase() == normalizedName,
        orElse: () => Country.parse(''), // Invalid fallback
      );

      if (match.countryCode.isNotEmpty) {
        return match.countryCode;
      }
    } catch (_) {
      // ignore and fallback
    }

    try {
      // Try using the `country_code` package as a fallback
      final code = CountryCode.tryParse(name);
      if (code != null) return code.alpha2;
    } catch (_) {
      // ignore
    }

    // If all lookups fail, return empty
    return '';
  }
}
