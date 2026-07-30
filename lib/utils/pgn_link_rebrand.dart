/// Canonical ChessEver host used when rebranding shared PGN.
const String kChesseverHost = 'chessever.com';

/// Hosts that may appear on Lichess-shaped URLs we rewrite (including already
/// host-swapped chessever.com paths that still use Lichess path shapes).
const String _linkHostAlt = r'(?:www\.)?(?:lichess\.(?:org|dev)|chessever\.com)';

/// Lichess hosts only (for residual host-only cleanup, e.g. annotator links).
final RegExp _lichessHostPattern = RegExp(
  r'lichess\.(?:org|dev)',
  caseSensitive: false,
);

/// Broadcast game URL (4 segments after /broadcast/):
/// `…/broadcast/{tourSlug}/{roundSlug}/{roundId}/{gameId}`
/// → `https://chessever.com/games/{gameId}`
final RegExp _broadcastGameUrlPattern = RegExp(
  'https?://$_linkHostAlt/broadcast/'
  r'([^/\s"#?]+)/([^/\s"#?]+)/([A-Za-z0-9]{8})/([A-Za-z0-9]{8})'
  r'(?=[/\s"#?]|$)',
  caseSensitive: false,
);

/// Broadcast round / tour URL (3 segments after /broadcast/):
/// `…/broadcast/{tourSlug}/{roundSlug}/{tourOrRoundId}`
/// → `https://chessever.com/broadcast/{tourSlug}/{tourOrRoundId}`
/// (web serves `/broadcast/[slug]/[id]`, not the Lichess round slug middle).
final RegExp _broadcastRoundUrlPattern = RegExp(
  'https?://$_linkHostAlt/broadcast/'
  r'([^/\s"#?]+)/([^/\s"#?]+)/([A-Za-z0-9]{8})'
  r'(?=[/\s"#?]|$)',
  caseSensitive: false,
);

/// Direct game URL: `…/{gameId}` (optionally /white|/black or query).
/// → `https://chessever.com/games/{gameId}`
/// Does not match paths that already start with `/games/` or `/broadcast/`.
final RegExp _directGameUrlPattern = RegExp(
  'https?://$_linkHostAlt/'
  r'([A-Za-z0-9]{8})'
  r'(?=(?:/(?:white|black))?(?:[?#\s"]|$))',
  caseSensitive: false,
);

/// Rewrites Lichess (and broken host-only ChessEver) URLs inside [pgn] to
/// routes the ChessEver web app actually serves:
/// - game → `/games/<id>`
/// - event/tour → `/broadcast/<slug>/<id>`
///
/// Touches header tag values and inline comments; move text is unaffected.
/// Idempotent for already-correct ChessEver URLs.
String rebrandPgnLinks(String pgn) {
  var out = pgn;

  // Order matters: longest broadcast game path before round path before bare id.
  out = out.replaceAllMapped(
    _broadcastGameUrlPattern,
    (m) => 'https://$kChesseverHost/games/${m[4]}',
  );

  out = out.replaceAllMapped(
    _broadcastRoundUrlPattern,
    (m) => 'https://$kChesseverHost/broadcast/${m[1]}/${m[3]}',
  );

  out = out.replaceAllMapped(_directGameUrlPattern, (m) {
    final id = m[1]!;
    // Skip if this 8-char token is already the /games/<id> id (would have
    // matched "games" as host path — pattern is host/ then 8-char, so
    // /games/XXXXXXXX is not matched). Safe to rewrite bare /XXXXXXXX.
    return 'https://$kChesseverHost/games/$id';
  });

  // Any remaining lichess.org / lichess.dev hosts (annotator, odd paths).
  out = out.replaceAll(_lichessHostPattern, kChesseverHost);

  return out;
}
