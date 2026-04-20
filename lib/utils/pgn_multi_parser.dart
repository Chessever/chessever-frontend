import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';

/// Splits a text blob that may contain one or more PGN games into individual
/// PGN strings (trimmed, without trailing whitespace).
///
/// Uses the `[Event` tag as a game boundary: each PGN must start with at least
/// one `[Event ...]` header (per the spec), so consecutive games in a
/// concatenated blob always have one. If no `[Event` headers are found, the
/// whole blob is returned as a single game (best-effort — `ChessGame.fromPgn`
/// can still parse header-less movetext).
List<String> splitPgnGames(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final trimmed = normalized.trim();
  if (trimmed.isEmpty) return const [];

  // Find all `[Event ...]` header positions that appear at the start of a line
  // (ignoring indentation). These mark the start of each game.
  final eventPattern = RegExp(r'^\[Event\s', multiLine: true);
  final matches = eventPattern.allMatches(trimmed).toList();

  if (matches.length <= 1) {
    return [trimmed];
  }

  final games = <String>[];
  for (var i = 0; i < matches.length; i++) {
    final start = matches[i].start;
    final end = (i + 1 < matches.length) ? matches[i + 1].start : trimmed.length;
    final game = trimmed.substring(start, end).trim();
    if (game.isNotEmpty) games.add(game);
  }

  return games;
}

/// Parsed PGN result, bundling the `ChessGame` alongside its raw PGN text.
class ParsedPgnEntry {
  final ChessGame chessGame;
  final String rawPgn;
  const ParsedPgnEntry({required this.chessGame, required this.rawPgn});
}

/// Parses a (possibly multi-game) PGN blob into a list of `ChessGame`s.
/// Invalid or empty entries are skipped; the result contains only games that
/// actually parsed to at least one legal move. Random text, FEN strings, or
/// PGN-like fragments with no playable moves return an empty list so callers
/// can surface a single "invalid PGN" error instead of routing to a preview
/// screen with ghost entries.
List<ParsedPgnEntry> parsePgnsToChessGames(String text) {
  final raw = splitPgnGames(text);
  final entries = <ParsedPgnEntry>[];
  for (var i = 0; i < raw.length; i++) {
    final pgn = raw[i];
    try {
      final game = ChessGame.fromPgn('imported_$i', pgn);
      if (game.mainline.isEmpty) continue;
      entries.add(ParsedPgnEntry(chessGame: game, rawPgn: pgn));
    } catch (_) {
      // Skip unparseable entries so a single bad game doesn't kill the batch.
    }
  }
  return entries;
}
