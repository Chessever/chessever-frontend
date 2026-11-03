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

  /// The title a player held WHEN THE GAME WAS PLAYED, from the game's own
  /// `WhiteTitle`/`BlackTitle` tags. A player's current title is the wrong
  /// answer for an old game: the 2014 IM who is a GM today.
  ///
  /// - This side's tag holds a title: it is the answer.
  /// - Only the opponent's tag holds one: the source writes title tags and
  ///   left this side out, which is how TWIC and Lichess say "untitled" then.
  /// - Neither does (no archive game before 2010 has one): [fallback], the
  ///   title the list row or the player profile carries.
  ///
  /// A placeholder (`-`, `?`) is no title tag at all: DGT LiveChess relays
  /// write `[WhiteTitle "-"]` for every player, titled or not. Gamebase
  /// resolves its own `whiteTitle`/`blackTitle` by the same rule.
  static String gameTimeTitle(
    Map<String, Object?> headers, {
    required bool isWhite,
    required String fallback,
  }) {
    final own = normalize(
      headers[isWhite ? 'WhiteTitle' : 'BlackTitle']?.toString(),
    );
    if (own.isNotEmpty) return own;
    final other = normalize(
      headers[isWhite ? 'BlackTitle' : 'WhiteTitle']?.toString(),
    );
    if (other.isNotEmpty) return '';
    return fallback;
  }

  /// Whether a game's two displayed titles are already the ones held when it
  /// was played. Gamebase resolves both together ([gameTimeTitle]), so once
  /// either side has a title the pair is settled: an empty side then means
  /// untitled at the time, and filling it with today's title is wrong.
  static bool titlesSettled(String? white, String? black) =>
      normalize(white).isNotEmpty || normalize(black).isNotEmpty;

  /// One side's title for a gamebase games-list row. [fallback] (today's
  /// title from a profile lookup) applies only when the row settles neither.
  static String listRowTitle(
    Map<String, dynamic> row, {
    required bool isWhite,
    String? fallback,
  }) {
    final white = normalize(row['whiteTitle']?.toString());
    final black = normalize(row['blackTitle']?.toString());
    if (white.isNotEmpty || black.isNotEmpty) return isWhite ? white : black;
    return normalize(fallback);
  }

  /// Whether the game's tags hold a real title for either side, which makes
  /// [gameTimeTitle] authoritative: an empty result then means "untitled at
  /// the time", not "unknown, look up today's title".
  static bool carriesTitles(Map<String, Object?> headers) =>
      normalize(headers['WhiteTitle']?.toString()).isNotEmpty ||
      normalize(headers['BlackTitle']?.toString()).isNotEmpty;

  static final RegExp _pgnTitleTag = RegExp(
    r'^\s*\[(White|Black)Title\s+"([^"]*)"\]',
    multiLine: true,
  );

  /// [carriesTitles] for a raw PGN string, without a full parse.
  static bool pgnCarriesTitles(String? pgn) {
    if (pgn == null || pgn.isEmpty) return false;
    return _pgnTitleTag
        .allMatches(pgn)
        .any((match) => normalize(match.group(2)).isNotEmpty);
  }

  /// Writes the card titles into a saved game's tags only when the game has
  /// no titles of its own. Overwriting them baked today's title into copies.
  static void fillMissingTitleTags(
    Map<String, dynamic> meta, {
    required String white,
    required String black,
  }) {
    if (carriesTitles(meta)) return;
    if (white.isNotEmpty) meta['WhiteTitle'] = white;
    if (black.isNotEmpty) meta['BlackTitle'] = black;
  }
}
