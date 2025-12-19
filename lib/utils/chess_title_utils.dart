class ChessTitleUtils {
  static String normalize(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';

    final upper = value.toUpperCase();
    if (upper == 'NONE' || upper == 'NULL') return '';

    // Already abbreviated.
    const known = {
      'GM',
      'IM',
      'FM',
      'CM',
      'WGM',
      'WIM',
      'WFM',
      'WCM',
    };
    if (known.contains(upper)) return upper;

    switch (upper) {
      case 'GRANDMASTER':
        return 'GM';
      case 'INTERNATIONAL MASTER':
        return 'IM';
      case 'FIDE MASTER':
        return 'FM';
      case 'CANDIDATE MASTER':
        return 'CM';
      case 'WOMAN GRANDMASTER':
        return 'WGM';
      case 'WOMAN INTERNATIONAL MASTER':
        return 'WIM';
      case 'WOMAN FIDE MASTER':
        return 'WFM';
      case 'WOMAN CANDIDATE MASTER':
        return 'WCM';
      default:
        return value; // Preserve unknown titles as-is.
    }
  }
}

