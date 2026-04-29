import 'package:dartchess/dartchess.dart';

class PgnPositionSnapshot {
  const PgnPositionSnapshot({
    required this.fen,
    required this.moveCount,
    required this.hasCustomStartingPosition,
    this.lastMoveUci,
  });

  final String fen;
  final int moveCount;
  final bool hasCustomStartingPosition;
  final String? lastMoveUci;
}

const int _kMaxPgnPositionCacheEntries = 500;
final Map<String, PgnPositionSnapshot> _pgnPositionCache = {};

bool isValidGameFen(String? fen) {
  final raw = fen?.trim();
  if (raw == null || raw.isEmpty) return false;

  try {
    Setup.parseFen(raw);
    return true;
  } catch (_) {
    return false;
  }
}

PgnPositionSnapshot? resolveFinalPositionFromPgn(String? pgn) {
  final raw = pgn?.trim();
  if (raw == null || raw.isEmpty) return null;

  final cached = _pgnPositionCache[raw];
  if (cached != null) return cached;

  try {
    final game = PgnGame.parsePgn(raw);
    var position = PgnGame.startingPosition(game.headers);
    Move? lastMove;
    var moveCount = 0;

    for (final node in game.moves.mainline()) {
      final move = position.parseSan(node.san);
      if (move == null) break;

      position = position.play(move);
      lastMove = move;
      moveCount++;
    }

    if (moveCount == 0) return null;

    final snapshot = PgnPositionSnapshot(
      fen: position.fen,
      moveCount: moveCount,
      hasCustomStartingPosition: game.headers.containsKey('FEN'),
      lastMoveUci: lastMove?.uci,
    );

    if (_pgnPositionCache.length >= _kMaxPgnPositionCacheEntries) {
      _pgnPositionCache.remove(_pgnPositionCache.keys.first);
    }
    _pgnPositionCache[raw] = snapshot;

    return snapshot;
  } catch (_) {
    return null;
  }
}

String? resolveFreshestGameFen({
  required String? fen,
  required String? pgn,
  required String? lastMove,
}) {
  final localFen = fen?.trim();
  final hasValidLocalFen = isValidGameFen(localFen);
  final pgnPosition = resolveFinalPositionFromPgn(pgn);

  if (pgnPosition == null) {
    return hasValidLocalFen ? localFen : null;
  }

  final normalizedLastMove = _normalizeUci(lastMove);
  final pgnMatchesLastMove =
      normalizedLastMove != null &&
      pgnPosition.lastMoveUci == normalizedLastMove;
  final localPly = plyFromFen(localFen);
  final pgnIsAtLeastAsAdvanced =
      pgnPosition.hasCustomStartingPosition ||
      localPly == null ||
      pgnPosition.moveCount >= localPly;

  if (!hasValidLocalFen) {
    return pgnPosition.fen;
  }

  // If PGN and last_move agree, PGN has reached the row's latest advertised
  // move. Prefer it over FEN so a separately lagging fen column cannot leave
  // cards one ply behind.
  if (pgnMatchesLastMove && pgnIsAtLeastAsAdvanced) {
    return pgnPosition.fen;
  }

  if (localPly != null && pgnPosition.moveCount > localPly) {
    return pgnPosition.fen;
  }

  return localFen;
}

int? plyFromFen(String? fen) {
  final parts = fen?.trim().split(RegExp(r'\s+'));
  if (parts == null || parts.length < 6) return null;

  final fullMove = int.tryParse(parts[5]);
  if (fullMove == null || fullMove <= 0) return null;

  final turn = parts[1];
  final blackToMoveOffset = turn == 'b' ? 1 : 0;
  return ((fullMove - 1) * 2) + blackToMoveOffset;
}

String? _normalizeUci(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.toLowerCase();
}
