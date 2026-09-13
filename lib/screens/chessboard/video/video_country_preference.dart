import 'video_languages.dart';
import 'video_stream.dart';

// Product fallback groups for commentary, not a claim that every resident
// speaks these languages. Explicit stream language takes precedence over flags.
const _languageCountries = <String, Set<String>>{
  'en': {
    'GB',
    'US',
    'CA',
    'AU',
    'NZ',
    'IE',
    'ZA',
    'IN',
    'SG',
    'PH',
    'NG',
    'KE',
  },
  'es': {
    'ES',
    'MX',
    'AR',
    'BO',
    'CL',
    'CO',
    'CR',
    'CU',
    'DO',
    'EC',
    'GT',
    'HN',
    'NI',
    'PA',
    'PE',
    'PR',
    'PY',
    'SV',
    'UY',
    'VE',
    'GQ',
  },
  'pt': {'PT', 'BR', 'AO', 'MZ', 'CV', 'GW', 'ST', 'TL'},
  'fr': {
    'FR',
    'BE',
    'CH',
    'CA',
    'LU',
    'MC',
    'SN',
    'CI',
    'CM',
    'CD',
    'CG',
    'GA',
    'BJ',
    'TG',
    'BF',
    'NE',
    'ML',
    'HT',
    'MG',
  },
  'de': {'DE', 'AT', 'CH', 'LI', 'LU'},
  'it': {'IT', 'CH', 'SM', 'VA'},
  'ar': {
    'SA',
    'AE',
    'BH',
    'DZ',
    'EG',
    'IQ',
    'JO',
    'KW',
    'LB',
    'LY',
    'MA',
    'OM',
    'PS',
    'QA',
    'SD',
    'SY',
    'TN',
    'YE',
  },
  'zh': {'CN', 'TW', 'HK', 'MO', 'SG'},
  'ko': {'KR', 'KP'},
  'ms': {'MY', 'BN', 'SG'},
};

String? normalizeVideoCountry(String? value) {
  final code = value?.trim().toUpperCase();
  return videoCountryNames.containsKey(code) ? code : null;
}

int videoCountryPriority(EventVideoStream stream, String? country) {
  final code = normalizeVideoCountry(country);
  if (code == null) return 2;
  if (stream.flagCode == code) return 0;
  final language = stream.inferredLanguage?.code;
  for (final group in _languageCountries.entries) {
    if (!group.value.contains(code)) continue;
    if (language != null
        ? language == group.key
        : group.value.contains(stream.flagCode)) {
      return 1;
    }
  }
  return 2;
}

List<EventVideoStream> prioritizeVideoCountry(
  List<EventVideoStream> streams,
  String? country, {
  String? countrymen,
}) {
  final ordered = orderVideoStreams(streams);
  int priority(EventVideoStream stream) {
    final saved = videoCountryPriority(stream, country);
    final local = videoCountryPriority(stream, countrymen);
    if (saved == 0) return 0;
    if (local == 0) return 1;
    if (saved == 1) return 2;
    if (local == 1) return 3;
    return 4;
  }

  return [
    for (var rank = 0; rank < 5; rank++)
      ...ordered.where((stream) => priority(stream) == rank),
  ];
}
