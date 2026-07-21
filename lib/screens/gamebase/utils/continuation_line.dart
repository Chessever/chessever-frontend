import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:dartchess/dartchess.dart';

/// A replayed continuation line: SAN labels plus the FEN after each ply.
///
/// Built from the `continuation` UCI slice the gamebase API attaches to
/// position-games rows when `notationPlies` is requested (Trello #984), or
/// from a full game PGN/payload when upgrading past the API's 20-ply cap.
class ContinuationLine {
  const ContinuationLine({required this.sans, required this.fens});

  /// SAN for each successfully replayed continuation ply.
  final List<String> sans;

  /// `fens[0]` is the anchor position; `fens[i]` is the position after
  /// applying `sans[0..i-1]`. Always `sans.length + 1` entries.
  final List<String> fens;

  bool get isEmpty => sans.isEmpty;
  bool get isNotEmpty => sans.isNotEmpty;
}

/// First four FEN fields (board, side, castling, ep) — enough to match a
/// position independent of halfmove/fullmove counters.
String continuationFenKey(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return fen.trim();
  return parts.take(4).join(' ');
}

/// Replays [ucis] from [anchorFen], converting each ply to SAN and collecting
/// the FEN after every move. Stops at the first move that fails to parse or is
/// illegal, returning the prefix replayed so far. Mirrors the tolerant
/// behavior of `uciToSanAndFen` in `move_statistics_panel.dart`.
ContinuationLine buildContinuationLine(String anchorFen, List<String> ucis) {
  Position position;
  try {
    position = Chess.fromSetup(Setup.parseFen(anchorFen));
  } catch (_) {
    return ContinuationLine(sans: const [], fens: [anchorFen]);
  }

  final sans = <String>[];
  final fens = <String>[anchorFen];
  for (final uci in ucis) {
    final trimmed = uci.trim().toLowerCase();
    if (trimmed.length < 4) break;
    try {
      final from = Square.fromName(trimmed.substring(0, 2));
      final to = Square.fromName(trimmed.substring(2, 4));
      Role? promotion;
      if (trimmed.length > 4) {
        promotion = Role.fromChar(trimmed[4]);
      }
      final move = NormalMove(from: from, to: to, promotion: promotion);
      final (next, san) = position.makeSan(move);
      position = next;
      sans.add(san);
      fens.add(position.fen);
    } catch (_) {
      break;
    }
  }
  return ContinuationLine(sans: sans, fens: fens);
}

/// Full-game continuation from [anchorFen] using a parsed [ChessGame] mainline.
///
/// Finds the first mainline position that matches [anchorFen], then returns
/// every remaining ply through the end of the game (no 20-ply API cap).
ContinuationLine buildContinuationLineFromChessGame(
  String anchorFen,
  ChessGame game,
) {
  final key = continuationFenKey(anchorFen);
  final mainline = game.mainline;
  if (mainline.isEmpty) {
    return ContinuationLine(sans: const [], fens: [anchorFen]);
  }

  // Index of the first move that is *after* the anchor position.
  var startIndex = 0;
  if (continuationFenKey(game.startingFen) == key) {
    startIndex = 0;
  } else {
    startIndex = -1;
    for (var i = 0; i < mainline.length; i++) {
      if (continuationFenKey(mainline[i].fen) == key) {
        startIndex = i + 1;
        break;
      }
    }
    if (startIndex < 0) {
      // Anchor not on this mainline (transposition / bad id) — keep empty
      // rather than dumping the whole game from move 1.
      return ContinuationLine(sans: const [], fens: [anchorFen]);
    }
  }

  if (startIndex >= mainline.length) {
    return ContinuationLine(sans: const [], fens: [anchorFen]);
  }

  final slice = mainline.sublist(startIndex);
  return ContinuationLine(
    sans: slice.map((m) => m.san).toList(growable: false),
    fens: [anchorFen, ...slice.map((m) => m.fen)],
  );
}

/// Prefer structured Gamebase `data` moves; fall back to [pgn] text.
///
/// Returns `null` when neither source yields a longer mainline than empty.
ContinuationLine? buildFullContinuationLine({
  required String anchorFen,
  required String gameId,
  Map<String, dynamic>? data,
  String? pgn,
}) {
  // 1) Structured payload (`sf` + `m[].u`) — same path openGamebaseGame uses.
  if (data != null && data.isNotEmpty) {
    final builtPgn = buildPgnFromGamebaseData(data);
    if (builtPgn != null && builtPgn.trim().isNotEmpty) {
      try {
        final game = ChessGame.fromPgn(gameId, builtPgn);
        final line = buildContinuationLineFromChessGame(anchorFen, game);
        if (line.isNotEmpty) return line;
      } catch (_) {}
    }
  }

  // 2) Raw PGN from includePgn.
  final raw = (pgn ?? '').trim();
  if (raw.isNotEmpty) {
    try {
      final game = ChessGame.fromPgn(gameId, raw);
      final line = buildContinuationLineFromChessGame(anchorFen, game);
      if (line.isNotEmpty) return line;
    } catch (_) {}
  }

  return null;
}

/// Label for continuation chip [index]: white plies get a `N.` prefix; a
/// leading black ply gets `N…` so the strip reads like real notation.
String continuationChipLabel(String anchorFen, int index, String san) {
  final parts = anchorFen.trim().split(RegExp(r'\s+'));
  final whiteToMove = parts.length > 1 ? parts[1] == 'w' : true;
  final baseMoveNumber =
      parts.length > 5 ? (int.tryParse(parts[5]) ?? 1) : 1;
  final isWhitePly = whiteToMove ? index.isEven : index.isOdd;
  final moveNumber = baseMoveNumber + ((whiteToMove ? index : index + 1) ~/ 2);
  if (isWhitePly) return '$moveNumber. $san';
  if (index == 0) return '$moveNumber… $san';
  return san;
}
