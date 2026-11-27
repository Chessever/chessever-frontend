import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/utils/pgn_game_splitter.dart';

export 'package:chessever2/utils/pgn_game_splitter.dart' show splitPgnGames;

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
      final game = ChessGame.fromPgn(importedGameId(pgn, i), pgn);
      if (game.mainline.isEmpty) continue;
      entries.add(ParsedPgnEntry(chessGame: game, rawPgn: pgn));
    } catch (_) {
      // Skip unparseable entries so a single bad game doesn't kill the batch.
    }
  }
  return entries;
}

/// The id of the [index]th game of an import, [pgn] its text. Its own per
/// game: the id is the game's identity for its board, its saved copies and
/// its likes, so two imports' first games must not share one. The same
/// game in the same place keeps it, so importing a file again finds what
/// was saved from it. FNV-1a, not [String.hashCode], which changes between
/// runs.
String importedGameId(String pgn, int index) {
  var hash = 0x811c9dc5;
  for (final unit in pgn.trim().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 'imported_${hash.toRadixString(16).padLeft(8, '0')}_$index';
}
