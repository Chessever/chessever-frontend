import 'package:chessever2/utils/country_utils.dart';

const int eventSearchPlaceholderCount = 7;

String eventSearchPlaceholderForIndex(int index, {String? countryCode}) {
  final normalizedCountry = _eventSearchCountryExample(countryCode);
  final placeholders = <String>[
    'Search',
    'Search by player: Caruana',
    'Search by opening: Ruy Lopez',
    'Search by ECO: B90',
    'Search by country: $normalizedCountry',
    'Search by title: GM',
    'Search by result: 1-0',
  ];

  return placeholders[index % placeholders.length];
}

String _eventSearchCountryExample(String? countryCode) {
  final trimmed = countryCode?.trim().toUpperCase();
  if (trimmed == null || trimmed.isEmpty) return 'AZE';
  if (trimmed.length == 2) return CountryUtils.toFideCode(trimmed);
  return trimmed;
}
