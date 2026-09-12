class ChessTitleUtils {
  static const Set<String> _knownShortTitles = {
    'GM',
    'IM',
    'FM',
    'CM',
    'WGM',
    'WIM',
    'WFM',
    'WCM',
  };

  static String normalize(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';

    final upper = value.toUpperCase();
    if (upper == 'NONE' || upper == 'NULL') return '';

    final normalized =
        upper
            .replaceAll(RegExp(r'[_/\-]+'), ' ')
            .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    // A value made only of separators and punctuation is a placeholder, not a
    // title. DGT LiveChess and the FIDE relay write `[WhiteTitle "-"]` for a
    // title they do not know, and PGN's own unknown is `?`; both used to fall
    // through to "preserve unknown titles as-is" and render as a badge.
    if (normalized.isEmpty) return '';

    if (_knownShortTitles.contains(normalized)) return normalized;

    bool hasWord(String word) =>
        RegExp(r'(^| )' + RegExp.escape(word) + r'( |$)').hasMatch(normalized);
    bool hasAll(Iterable<String> words) => words.every(hasWord);

    // Prefer woman-title variants first to handle malformed combined strings
    // like "International Master Woman Grandmaster".
    if (hasWord('WGM') ||
        (hasWord('WOMAN') &&
            (hasWord('GRANDMASTER') || hasAll(['GRAND', 'MASTER'])))) {
      return 'WGM';
    }
    if (hasWord('WIM') ||
        (hasWord('WOMAN') && hasAll(['INTERNATIONAL', 'MASTER']))) {
      return 'WIM';
    }
    if (hasWord('WFM') || (hasWord('WOMAN') && hasAll(['FIDE', 'MASTER']))) {
      return 'WFM';
    }
    if (hasWord('WCM') ||
        (hasWord('WOMAN') && hasAll(['CANDIDATE', 'MASTER']))) {
      return 'WCM';
    }

    if (hasWord('GM') ||
        hasWord('GRANDMASTER') ||
        hasAll(['GRAND', 'MASTER'])) {
      return 'GM';
    }
    if (hasWord('IM') || hasAll(['INTERNATIONAL', 'MASTER'])) {
      return 'IM';
    }
    if (hasWord('FM') || hasAll(['FIDE', 'MASTER'])) {
      return 'FM';
    }
    if (hasWord('CM') || hasAll(['CANDIDATE', 'MASTER'])) {
      return 'CM';
    }

    return value; // Preserve unknown titles as-is.
  }
}
