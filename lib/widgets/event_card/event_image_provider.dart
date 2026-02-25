import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Result containing image URL and fallback country code for events without images
class EventImageData {
  final String? imageUrl;
  final String? fallbackCountryCode;

  const EventImageData({this.imageUrl, this.fallbackCountryCode});

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// True if we have either an image or a valid fallback country flag
  bool get hasVisual =>
      hasImage ||
      (fallbackCountryCode != null && fallbackCountryCode!.isNotEmpty);
}

/// Fetches the image URL and fallback country for a group broadcast event
/// Returns the first tour's image from the tours table, or a country code
/// derived from location or dominant player federation if no image exists
final eventImageProvider = FutureProvider.autoDispose
    .family<EventImageData, String>((ref, groupBroadcastId) async {
      try {
        final tourRepo = ref.read(tourRepositoryProvider);
        final tours = await tourRepo.getTourByGroupId(groupBroadcastId);

        if (tours.isEmpty) {
          return const EventImageData();
        }

        final tour = tours.first;

        // If tour has an image, return it
        if (tour.image != null && tour.image!.isNotEmpty) {
          return EventImageData(imageUrl: tour.image);
        }

        // No image - try to get country from location or player federations
        String? countryCode = _extractCountryFromLocation(tour.info.location);

        // If no location, try to find dominant player federation
        if (countryCode == null && tour.players.isNotEmpty) {
          countryCode = _getDominantFederation(tour.players);
        }

        return EventImageData(fallbackCountryCode: countryCode);
      } catch (e) {
        debugPrint(
          '[EventImageProvider] Error fetching image for $groupBroadcastId: $e',
        );
        return const EventImageData();
      }
    });

/// Extracts a 2-letter country code from location string
String? _extractCountryFromLocation(String? location) {
  if (location == null || location.trim().isEmpty) return null;

  final trimmed = location.trim();

  // Common location patterns: "City, Country" or just "Country"
  // Try the last part after comma first
  final parts = trimmed.split(',');
  for (final part in parts.reversed) {
    final cleaned = part.trim();
    if (cleaned.isEmpty) continue;

    // Check if it's already a 2 or 3 letter code
    final upper = cleaned.toUpperCase();
    if (upper.length == 2) {
      return upper;
    }
    if (upper.length == 3) {
      // Try to convert 3-letter to 2-letter code
      final iso2 = _fideToIso2[upper];
      if (iso2 != null) return iso2;
    }

    // Check common country names
    final fromName = _countryNameToCode[cleaned.toLowerCase()];
    if (fromName != null) return fromName;
  }

  return null;
}

/// Finds the dominant federation among players (if >50% from same country)
String? _getDominantFederation(List players) {
  if (players.isEmpty) return null;

  final federationCounts = <String, int>{};
  int totalWithFed = 0;

  for (final player in players) {
    final fed = player.federation;
    if (fed != null && fed.isNotEmpty) {
      totalWithFed++;
      federationCounts[fed] = (federationCounts[fed] ?? 0) + 1;
    }
  }

  if (totalWithFed == 0) return null;

  // Find the most common federation
  String? dominant;
  int maxCount = 0;
  for (final entry in federationCounts.entries) {
    if (entry.value > maxCount) {
      maxCount = entry.value;
      dominant = entry.key;
    }
  }

  // Only use if >50% of players are from this federation
  if (dominant != null && maxCount / totalWithFed > 0.5) {
    // Convert 3-letter FIDE code to 2-letter ISO if needed
    if (dominant.length == 3) {
      return _fideToIso2[dominant.toUpperCase()] ?? dominant.substring(0, 2);
    }
    return dominant.toUpperCase();
  }

  return null;
}

/// Common FIDE 3-letter to ISO 2-letter code mappings
const _fideToIso2 = {
  'USA': 'US',
  'GER': 'DE',
  'FRA': 'FR',
  'ENG': 'GB',
  'ESP': 'ES',
  'ITA': 'IT',
  'NED': 'NL',
  'POL': 'PL',
  'RUS': 'RU',
  'UKR': 'UA',
  'CHN': 'CN',
  'IND': 'IN',
  'NOR': 'NO',
  'SWE': 'SE',
  'DEN': 'DK',
  'FIN': 'FI',
  'AUT': 'AT',
  'SUI': 'CH',
  'BEL': 'BE',
  'CZE': 'CZ',
  'HUN': 'HU',
  'ROU': 'RO',
  'BUL': 'BG',
  'SRB': 'RS',
  'CRO': 'HR',
  'SLO': 'SI',
  'SVK': 'SK',
  'GRE': 'GR',
  'TUR': 'TR',
  'ISR': 'IL',
  'ARM': 'AM',
  'GEO': 'GE',
  'AZE': 'AZ',
  'KAZ': 'KZ',
  'UZB': 'UZ',
  'ARG': 'AR',
  'BRA': 'BR',
  'PER': 'PE',
  'COL': 'CO',
  'CUB': 'CU',
  'MEX': 'MX',
  'CAN': 'CA',
  'AUS': 'AU',
  'NZL': 'NZ',
  'RSA': 'ZA',
  'EGY': 'EG',
  'VIE': 'VN',
  'PHI': 'PH',
  'INA': 'ID',
  'MAS': 'MY',
  'SGP': 'SG',
  'JPN': 'JP',
  'KOR': 'KR',
  'IRI': 'IR',
  'POR': 'PT',
  'IRL': 'IE',
  'SCO': 'GB',
  'WLS': 'GB',
  'LTU': 'LT',
  'LAT': 'LV',
  'EST': 'EE',
  'BLR': 'BY',
  'MDA': 'MD',
  'MNE': 'ME',
  'MKD': 'MK',
  'BIH': 'BA',
  'ALB': 'AL',
  'LUX': 'LU',
  'ISL': 'IS',
  'CYP': 'CY',
  'MLT': 'MT',
  'AND': 'AD',
  'MON': 'MC',
  'LIE': 'LI',
  'FAI': 'FO',
};

/// Common country name to ISO 2-letter code mappings
const _countryNameToCode = {
  'united states': 'US',
  'usa': 'US',
  'american': 'US',
  'germany': 'DE',
  'german': 'DE',
  'france': 'FR',
  'french': 'FR',
  'england': 'GB',
  'english': 'GB',
  'british': 'GB',
  'uk': 'GB',
  'united kingdom': 'GB',
  'spain': 'ES',
  'spanish': 'ES',
  'italy': 'IT',
  'italian': 'IT',
  'netherlands': 'NL',
  'dutch': 'NL',
  'holland': 'NL',
  'poland': 'PL',
  'polish': 'PL',
  'russia': 'RU',
  'russian': 'RU',
  'ukraine': 'UA',
  'ukrainian': 'UA',
  'china': 'CN',
  'chinese': 'CN',
  'india': 'IN',
  'indian': 'IN',
  'norway': 'NO',
  'norwegian': 'NO',
  'sweden': 'SE',
  'swedish': 'SE',
  'denmark': 'DK',
  'danish': 'DK',
  'finland': 'FI',
  'finnish': 'FI',
  'austria': 'AT',
  'austrian': 'AT',
  'switzerland': 'CH',
  'swiss': 'CH',
  'belgium': 'BE',
  'belgian': 'BE',
  'czech republic': 'CZ',
  'czechia': 'CZ',
  'czech': 'CZ',
  'hungary': 'HU',
  'hungarian': 'HU',
  'romania': 'RO',
  'romanian': 'RO',
  'bulgaria': 'BG',
  'bulgarian': 'BG',
  'serbia': 'RS',
  'serbian': 'RS',
  'croatia': 'HR',
  'croatian': 'HR',
  'slovenia': 'SI',
  'slovenian': 'SI',
  'slovakia': 'SK',
  'slovak': 'SK',
  'greece': 'GR',
  'greek': 'GR',
  'turkey': 'TR',
  'turkish': 'TR',
  'israel': 'IL',
  'israeli': 'IL',
  'armenia': 'AM',
  'armenian': 'AM',
  'georgia': 'GE',
  'georgian': 'GE',
  'azerbaijan': 'AZ',
  'azeri': 'AZ',
  'kazakhstan': 'KZ',
  'kazakh': 'KZ',
  'uzbekistan': 'UZ',
  'uzbek': 'UZ',
  'argentina': 'AR',
  'argentine': 'AR',
  'brazil': 'BR',
  'brazilian': 'BR',
  'peru': 'PE',
  'peruvian': 'PE',
  'colombia': 'CO',
  'colombian': 'CO',
  'cuba': 'CU',
  'cuban': 'CU',
  'mexico': 'MX',
  'mexican': 'MX',
  'canada': 'CA',
  'canadian': 'CA',
  'australia': 'AU',
  'australian': 'AU',
  'new zealand': 'NZ',
  'south africa': 'ZA',
  'egypt': 'EG',
  'egyptian': 'EG',
  'vietnam': 'VN',
  'vietnamese': 'VN',
  'philippines': 'PH',
  'filipino': 'PH',
  'philippine': 'PH',
  'indonesia': 'ID',
  'indonesian': 'ID',
  'malaysia': 'MY',
  'malaysian': 'MY',
  'singapore': 'SG',
  'singaporean': 'SG',
  'japan': 'JP',
  'japanese': 'JP',
  'south korea': 'KR',
  'korea': 'KR',
  'korean': 'KR',
  'iran': 'IR',
  'iranian': 'IR',
  'portugal': 'PT',
  'portuguese': 'PT',
  'ireland': 'IE',
  'irish': 'IE',
  'scotland': 'GB',
  'scottish': 'GB',
  'wales': 'GB',
  'welsh': 'GB',
  'lithuania': 'LT',
  'lithuanian': 'LT',
  'latvia': 'LV',
  'latvian': 'LV',
  'estonia': 'EE',
  'estonian': 'EE',
  'belarus': 'BY',
  'belarusian': 'BY',
  'moldova': 'MD',
  'moldovan': 'MD',
  'montenegro': 'ME',
  'north macedonia': 'MK',
  'macedonia': 'MK',
  'macedonian': 'MK',
  'bosnia': 'BA',
  'bosnian': 'BA',
  'albania': 'AL',
  'albanian': 'AL',
  'luxembourg': 'LU',
  'iceland': 'IS',
  'icelandic': 'IS',
  'cyprus': 'CY',
  'malta': 'MT',
  'andorra': 'AD',
  'monaco': 'MC',
  'liechtenstein': 'LI',
  // Middle East & Gulf countries
  'oman': 'OM',
  'omani': 'OM',
  'uae': 'AE',
  'emirates': 'AE',
  'dubai': 'AE',
  'abu dhabi': 'AE',
  'qatar': 'QA',
  'qatari': 'QA',
  'saudi arabia': 'SA',
  'saudi': 'SA',
  'bahrain': 'BH',
  'kuwait': 'KW',
  'kuwaiti': 'KW',
  'jordan': 'JO',
  'jordanian': 'JO',
  'lebanon': 'LB',
  'lebanese': 'LB',
  'syria': 'SY',
  'syrian': 'SY',
  'iraq': 'IQ',
  'iraqi': 'IQ',
  // Central Asian countries
  'tajikistan': 'TJ',
  'tajik': 'TJ',
  'turkmenistan': 'TM',
  'kyrgyzstan': 'KG',
  'kyrgyz': 'KG',
  'mongolia': 'MN',
  'mongolian': 'MN',
  // Southeast Asian countries
  'thailand': 'TH',
  'thai': 'TH',
  'myanmar': 'MM',
  'cambodia': 'KH',
  'laos': 'LA',
  // African countries
  'morocco': 'MA',
  'moroccan': 'MA',
  'tunisia': 'TN',
  'tunisian': 'TN',
  'algeria': 'DZ',
  'algerian': 'DZ',
  'nigeria': 'NG',
  'nigerian': 'NG',
  'kenya': 'KE',
  'kenyan': 'KE',
  'ghana': 'GH',
  'ghanaian': 'GH',
  'zimbabwe': 'ZW',
  // Latin American countries
  'chile': 'CL',
  'chilean': 'CL',
  'venezuela': 'VE',
  'venezuelan': 'VE',
  'ecuador': 'EC',
  'ecuadorian': 'EC',
  'uruguay': 'UY',
  'uruguayan': 'UY',
  'paraguay': 'PY',
  'paraguayan': 'PY',
  'bolivia': 'BO',
  'bolivian': 'BO',
  'costa rica': 'CR',
  'panama': 'PA',
  // Caribbean
  'puerto rico': 'PR',
  'dominican': 'DO',
  'jamaica': 'JM',
  'jamaican': 'JM',
  'trinidad': 'TT',
  // Nordic
  'faroe': 'FO',
  'faroese': 'FO',
};
