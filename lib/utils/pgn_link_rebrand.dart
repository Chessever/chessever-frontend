/// Canonical Chessever host used when rebranding shared PGN.
const String kChesseverHost = 'chessever.com';

/// Lichess hosts that leak into broadcast-sourced PGN headers
/// (`Site`/`GameURL`/`BroadcastURL`/`ChapterURL`/`Annotator`, plus the
/// occasional `.dev` staging host and inline comment links).
final RegExp _lichessHostPattern = RegExp(
  r'lichess\.(?:org|dev)',
  caseSensitive: false,
);

/// Rewrites every Lichess host reference inside [pgn] to [kChesseverHost] so
/// PGN we share/copy/export never exposes third-party (Lichess) links.
///
/// Only the host is swapped — paths are preserved, so the URLs keep mirroring
/// Lichess' broadcast structure on chessever.com, matching the convention used
/// by the event/game share URLs.
///
/// Touches header tag values and inline comments alike; move text never
/// contains a host so it is unaffected. Idempotent.
String rebrandPgnLinks(String pgn) =>
    pgn.replaceAll(_lichessHostPattern, kChesseverHost);
