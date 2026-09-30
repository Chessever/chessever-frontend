import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart'
    show GameMoveClassification;
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart'
    show classificationFromNags, legacyClassificationFromComments;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// `[%eval 0.35]`, `[%eval -1.20,24]`, `[%eval #-3]`. Group 1 is the mate
/// marker, group 2 the number. Same shape [ChessGame.fromPgn] reads, parsed
/// straight to integers here so Feed never re-parses strings per frame.
final RegExp _evalDirective = RegExp(
  r'\[%eval\s+(#)?([+-]?\d+(?:\.\d+)?)(?:,\d+)?\s*\]',
);

/// One mainline move of a Feed game, with everything the moment detector needs.
///
/// Positions are kept (not just FENs) because the heuristics replay material,
/// attack maps and exchanges; re-parsing a FEN per question would dominate the
/// cost of a clip.
@immutable
class FeedPgnMove {
  const FeedPgnMove({
    required this.ply,
    required this.before,
    required this.after,
    required this.move,
    required this.san,
    required this.uci,
    this.cp,
    this.mate,
    this.nags = const <int>[],
    this.classification,
  });

  /// 1-based: ply 1 is White's first move (or the first move after a FEN).
  final int ply;
  final Position before;
  final Position after;
  final Move move;
  final String san;

  /// dartchess UCI. Castling is king-to-rook (`e1h1`), matching [ChessGame].
  final String uci;

  /// White-POV centipawns after the move, from `[%eval]`.
  final int? cp;

  /// White-POV mate distance after the move (positive = White mates).
  final int? mate;
  final List<int> nags;

  /// ChessEver report class carried by the `$240`–`$247` block (or the legacy
  /// comment directive), when the PGN was exported from a finished report.
  final GameMoveClassification? classification;

  Side get mover => before.turn;
  bool get hasEval => cp != null || mate != null;

  /// The move's class as the PGN carries it: the report verdict (block NAG or
  /// legacy directive) first, else a standard glyph NAG via [moveClassFromNags].
  MoveClass? get moveClass {
    final verdict = classification;
    if (verdict != null) return moveClassFromClassification(verdict);
    return moveClassFromNags(nags);
  }
}

/// A parsed mainline, ready for [detectFlowMoments].
@immutable
class FeedPgnGame {
  const FeedPgnGame({
    required this.start,
    required this.moves,
    required this.headers,
    this.result,
  });

  final Position start;
  final List<FeedPgnMove> moves;
  final Map<String, String> headers;

  /// Normalised `1-0`, `0-1`, `½-½`, or null while unfinished / unknown.
  final String? result;

  bool get hasEvals => moves.any((move) => move.hasEval);

  /// Whether any move carries a ChessEver report classification.
  bool get hasReportClassifications =>
      moves.any((move) => move.classification != null);

  /// Side that won, or null for a draw / unknown result.
  Side? get winner => switch (result) {
    '1-0' => Side.white,
    '0-1' => Side.black,
    _ => null,
  };
}

/// Normalises a PGN / database result token to `1-0`, `0-1`, `½-½` or null.
String? normalizeFlowResult(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  switch (value) {
    case '1-0':
    case 'W':
      return '1-0';
    case '0-1':
    case 'B':
      return '0-1';
    case '1/2-1/2':
    case '½-½':
    case '1/2':
    case 'D':
      return '½-½';
  }
  return null;
}

/// Parses `[%eval]` out of a move's comments into White-POV (cp, mate).
({int? cp, int? mate}) parseFlowEval(Iterable<String>? comments) {
  if (comments == null) return (cp: null, mate: null);
  for (final comment in comments) {
    final match = _evalDirective.firstMatch(comment);
    if (match == null) continue;
    final number = match.group(2)!;
    if (match.group(1) != null) {
      final mate = int.tryParse(number.replaceFirst('+', ''));
      // `#0` is a finished game; lichess drops it and so do we.
      if (mate != null && mate != 0) return (cp: null, mate: mate);
      return (cp: null, mate: null);
    }
    final pawns = double.tryParse(number);
    if (pawns != null) return (cp: (pawns * 100).round(), mate: null);
  }
  return (cp: null, mate: null);
}

/// Parses [pgn]'s mainline for Feed. Variations are ignored — a clip only ever
/// plays the game as it happened — which also keeps this far cheaper than
/// [ChessGame.fromPgn] on annotated PGNs.
///
/// Stops at the first illegal/unparseable SAN rather than throwing, so a
/// damaged tail still yields the playable prefix. Returns null when the PGN
/// has no playable moves at all or its start position is invalid.
FeedPgnGame? parseFlowPgn(String pgn, {int maxPlies = 400}) {
  final trimmed = pgn.trim();
  if (trimmed.isEmpty) return null;

  final PgnGame<PgnNodeData> parsed;
  final Position start;
  try {
    parsed = PgnGame.parsePgn(trimmed);
    start = PgnGame.startingPosition(parsed.headers);
  } catch (_) {
    return null;
  }

  final moves = <FeedPgnMove>[];
  var position = start;
  PgnNode<PgnNodeData> node = parsed.moves;
  while (node.children.isNotEmpty && moves.length < maxPlies) {
    final child = node.children.first;
    final data = child.data;
    final Move? move;
    final Position next;
    try {
      move = position.parseSan(data.san);
      if (move == null) break;
      next = position.play(move);
    } catch (_) {
      break;
    }
    final eval = parseFlowEval(data.comments);
    final nags = data.nags ?? const <int>[];
    moves.add(
      FeedPgnMove(
        ply: moves.length + 1,
        before: position,
        after: next,
        move: move,
        san: data.san,
        uci: move.uci,
        cp: eval.cp,
        mate: eval.mate,
        nags: nags,
        classification:
            classificationFromNags(nags) ??
            legacyClassificationFromComments(data.comments),
      ),
    );
    position = next;
    node = child;
  }

  if (moves.isEmpty) return null;

  var result = normalizeFlowResult(parsed.headers['Result']);
  // A mate on the board settles the result even when the header says `*`.
  final last = moves.last.after;
  if (result == null && last.isCheckmate) {
    result = last.turn == Side.white ? '0-1' : '1-0';
  }
  if (result == null && (last.isStalemate || last.isInsufficientMaterial)) {
    result = '½-½';
  }

  return FeedPgnGame(
    start: start,
    moves: List.unmodifiable(moves),
    headers: Map.unmodifiable(parsed.headers),
    result: result,
  );
}
