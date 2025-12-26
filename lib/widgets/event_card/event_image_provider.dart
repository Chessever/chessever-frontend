import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Result containing image URL and fallback country code for events without images
class EventImageData {
  final String? imageUrl;
  final String? fallbackCountryCode;

  const EventImageData({this.imageUrl, this.fallbackCountryCode});

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
}

/// Fetches the image URL and fallback country for a group broadcast event
/// Returns the first tour's image from the tours table, or a country code
/// derived from location or dominant player federation if no image exists
final eventImageProvider =
    FutureProvider.autoDispose.family<EventImageData, String>(
  (ref, groupBroadcastId) async {
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
  },
);

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
  'germany': 'DE',
  'france': 'FR',
  'england': 'GB',
  'uk': 'GB',
  'united kingdom': 'GB',
  'spain': 'ES',
  'italy': 'IT',
  'netherlands': 'NL',
  'holland': 'NL',
  'poland': 'PL',
  'russia': 'RU',
  'ukraine': 'UA',
  'china': 'CN',
  'india': 'IN',
  'norway': 'NO',
  'sweden': 'SE',
  'denmark': 'DK',
  'finland': 'FI',
  'austria': 'AT',
  'switzerland': 'CH',
  'belgium': 'BE',
  'czech republic': 'CZ',
  'czechia': 'CZ',
  'hungary': 'HU',
  'romania': 'RO',
  'bulgaria': 'BG',
  'serbia': 'RS',
  'croatia': 'HR',
  'slovenia': 'SI',
  'slovakia': 'SK',
  'greece': 'GR',
  'turkey': 'TR',
  'israel': 'IL',
  'armenia': 'AM',
  'georgia': 'GE',
  'azerbaijan': 'AZ',
  'kazakhstan': 'KZ',
  'uzbekistan': 'UZ',
  'argentina': 'AR',
  'brazil': 'BR',
  'peru': 'PE',
  'colombia': 'CO',
  'cuba': 'CU',
  'mexico': 'MX',
  'canada': 'CA',
  'australia': 'AU',
  'new zealand': 'NZ',
  'south africa': 'ZA',
  'egypt': 'EG',
  'vietnam': 'VN',
  'philippines': 'PH',
  'indonesia': 'ID',
  'malaysia': 'MY',
  'singapore': 'SG',
  'japan': 'JP',
  'south korea': 'KR',
  'korea': 'KR',
  'iran': 'IR',
  'portugal': 'PT',
  'ireland': 'IE',
  'scotland': 'GB',
  'wales': 'GB',
  'lithuania': 'LT',
  'latvia': 'LV',
  'estonia': 'EE',
  'belarus': 'BY',
  'moldova': 'MD',
  'montenegro': 'ME',
  'north macedonia': 'MK',
  'macedonia': 'MK',
  'bosnia': 'BA',
  'albania': 'AL',
  'luxembourg': 'LU',
  'iceland': 'IS',
  'cyprus': 'CY',
  'malta': 'MT',
  'andorra': 'AD',
  'monaco': 'MC',
  'liechtenstein': 'LI',
};
