import 'package:dartchess/dartchess.dart';

class PgnPositionSnapshot {
  const PgnPositionSnapshot({
    required this.fen,
    required this.moveCount,
    required this.hasCustomStartingPosition,
    this.lastMoveUci,
    this.finalEval,
  });

  final String fen;
  final int moveCount;
  final bool hasCustomStartingPosition;
  final String? lastMoveUci;

  /// The `[%eval]` recorded after the last move, i.e. for [fen] (a saved
  /// report writes one after every move). White's side.
  final PgnEvaluation? finalEval;
}

const int _kMaxPgnPositionCacheEntries = 500;
final Map<String, PgnPositionSnapshot> _pgnPositionCache = {};

// PGNs that resolve to no position (no moves yet, or unparseable). Every
// function here is pure in its string arguments and runs inside card builds,
// so a not-started game must not be parsed again on each rebuild.
final Set<String> _unresolvablePgns = {};

const int _kMaxFenValidityCacheEntries = 1000;
final Map<String, bool> _fenValidityCache = {};

final RegExp _whitespaceRun = RegExp(r'\s+');

bool isValidGameFen(String? fen) {
  final raw = fen?.trim();
  if (raw == null || raw.isEmpty) return false;

  final cached = _fenValidityCache[raw];
  if (cached != null) return cached;

  bool valid;
  try {
    Setup.parseFen(raw);
    valid = true;
  } catch (_) {
    valid = false;
  }
  if (_fenValidityCache.length >= _kMaxFenValidityCacheEntries) {
    _fenValidityCache.remove(_fenValidityCache.keys.first);
  }
  return _fenValidityCache[raw] = valid;
}

PgnPositionSnapshot? resolveFinalPositionFromPgn(String? pgn) {
  if (pgn == null) return null;

  // Look up the string as given first. trim() allocates a new string whenever
  // the PGN has edge whitespace, and a new string re-hashes the whole PGN on
  // every lookup.
  final direct = _pgnPositionCache[pgn];
  if (direct != null) return direct;
  if (_unresolvablePgns.contains(pgn)) return null;

  final raw = pgn.trim();
  if (raw.isEmpty) return null;

  final cached = _pgnPositionCache[raw];
  if (cached != null) {
    if (!identical(raw, pgn)) _rememberPgnPosition(pgn, cached);
    return cached;
  }

  final snapshot = _replayPgn(raw);
  if (snapshot == null) {
    if (_unresolvablePgns.length >= _kMaxPgnPositionCacheEntries) {
      _unresolvablePgns.remove(_unresolvablePgns.first);
    }
    _unresolvablePgns.add(pgn);
    return null;
  }

  _rememberPgnPosition(raw, snapshot);
  if (!identical(raw, pgn)) _rememberPgnPosition(pgn, snapshot);
  return snapshot;
}

void _rememberPgnPosition(String key, PgnPositionSnapshot snapshot) {
  if (_pgnPositionCache.length >= _kMaxPgnPositionCacheEntries) {
    _pgnPositionCache.remove(_pgnPositionCache.keys.first);
  }
  _pgnPositionCache[key] = snapshot;
}

PgnPositionSnapshot? _replayPgn(String raw) {
  try {
    final game = PgnGame.parsePgn(raw);
    var position = PgnGame.startingPosition(game.headers);
    Move? lastMove;
    PgnNodeData? lastNode;
    var moveCount = 0;

    for (final node in game.moves.mainline()) {
      final move = position.parseSan(node.san);
      if (move == null) break;

      position = position.play(move);
      lastMove = move;
      lastNode = node;
      moveCount++;
    }

    if (moveCount == 0) return null;

    final snapshot = PgnPositionSnapshot(
      fen: position.fen,
      moveCount: moveCount,
      hasCustomStartingPosition: game.headers.containsKey('FEN'),
      lastMoveUci: lastMove?.uci,
      // Only the final move's comments are read: this runs for every live
      // card's PGN, so the replay stays as cheap as before.
      finalEval: _recordedEval(lastNode?.comments),
    );

    return snapshot;
  } catch (_) {
    return null;
  }
}

PgnEvaluation? _recordedEval(List<String>? comments) {
  for (final comment in comments ?? const <String>[]) {
    final eval = PgnComment.fromPgn(comment).eval;
    if (eval != null) return eval;
  }
  return null;
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
  final parts = fen?.trim().split(_whitespaceRun);
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
