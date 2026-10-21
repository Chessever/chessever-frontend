/// Search matching shared by the Standings (players) and team standings tabs.
///
/// Official tables carry names in every script (Chess-Results publishes
/// Cyrillic, CJK and accented Latin names verbatim) while the broadcast feed
/// often transliterates them ("Müller" vs "Mueller"). An ASCII-only filter
/// erased non-Latin queries entirely, so typing a Chinese or Russian name
/// matched every row. Here letters and digits of every script survive,
/// Latin diacritics fold to their base letter, and German umlauts also match
/// their two-letter transliteration.
library;

final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _combiningMarks = RegExp(r'[̀-ͯ]');

const Map<String, String> _latinFold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'ă': 'a', 'ą': 'a', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ĉ': 'c', 'ċ': 'c',
  'ď': 'd', 'đ': 'd', 'ð': 'd', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e', 'ĕ': 'e', 'ğ': 'g', 'ĝ': 'g',
  'ġ': 'g', 'ģ': 'g', 'ĥ': 'h', 'ħ': 'h', 'ì': 'i', 'í': 'i', 'î': 'i',
  'ï': 'i', 'ī': 'i', 'į': 'i', 'ı': 'i', 'ĩ': 'i', 'ĭ': 'i', 'ĵ': 'j',
  'ķ': 'k', 'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ŀ': 'l', 'ł': 'l', 'ñ': 'n',
  'ń': 'n', 'ņ': 'n', 'ň': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
  'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o', 'ŏ': 'o', 'ŕ': 'r', 'ř': 'r',
  'ŗ': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ș': 's', 'ŝ': 's', 'ť': 't',
  'ţ': 't', 'ț': 't', 'ŧ': 't', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u', 'ũ': 'u', 'ŭ': 'u', 'ý': 'y',
  'ÿ': 'y', 'ŷ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z', 'ß': 'ss', 'æ': 'ae',
  'œ': 'oe', 'þ': 'th',
};

const Map<String, String> _germanFold = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue'};

String _fold(String lower, {required bool german}) {
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write((german ? _germanFold[char] : null) ?? _latinFold[char] ?? char);
  }
  return out.toString();
}

String _collapse(String value) => value
    .replaceAll(_combiningMarks, '')
    .replaceAll(_nonWord, ' ')
    .trim()
    .split(' ')
    .where((part) => part.isNotEmpty)
    .join(' ');

/// The searchable spellings of [value]: diacritics folded to the base letter,
/// plus the German two-letter umlaut form when it differs.
Set<String> standingsSearchForms(String value) {
  final lower = value.toLowerCase();
  return {
    _collapse(_fold(lower, german: false)),
    _collapse(_fold(lower, german: true)),
  }..remove('');
}

/// Whether [value] matches [query] as a whole phrase or token by token, in any
/// script and regardless of Latin diacritics or umlaut transliteration.
bool matchesStandingsSearch(String value, String query) {
  final queries = standingsSearchForms(query);
  if (queries.isEmpty) return true;
  final values = standingsSearchForms(value);
  for (final v in values) {
    for (final q in queries) {
      if (v.contains(q)) return true;
      if (q.split(' ').every(v.contains)) return true;
    }
  }
  return false;
}
