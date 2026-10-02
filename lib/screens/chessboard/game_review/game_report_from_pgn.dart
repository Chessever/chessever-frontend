import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart'
    show chesseverClassificationsFromMainline;

/// Restores the report already saved with a game, without running an engine.
/// Ordinary PGN glyphs and partial evaluations are not a completed report.
///
/// [whiteRating] and [blackRating] are the players' known ratings, which the
/// estimated game rating is anchored to exactly as a fresh analysis does.
GameAnalysisReport? gameAnalysisReportFromPgn(
  ChessGame game, {
  int? whiteRating,
  int? blackRating,
}) {
  final source = game.analysisCleared ? game.analysisBackup?.game : game;
  if (source == null || source.mainline.isEmpty) return null;
  final fingerprint = gameReportFingerprint(game);
  if (gameReportFingerprint(source) != fingerprint) return null;
  final classifications = chesseverClassificationsFromMainline(source);
  if (classifications.isEmpty) return null;

  // PGN reports carry each played position's score, but not the initial
  // position's score or any search lines. Accuracy and the estimated ratings
  // are not written either; [recoverGameReportSummary] derives them again.
  final positions = <GameReportPosition>[
    GameReportPosition(
      fen: source.startingFen,
      lines: const [GameReportLine(moves: [], depth: 0)],
    ),
  ];
  final moves = <GameReportMove>[];
  for (var i = 0; i < source.mainline.length; i++) {
    final move = source.mainline[i];
    final evaluation = _savedEvaluation(move.eval);
    if (evaluation == null) return null;
    positions.add(GameReportPosition(fen: move.fen, lines: [evaluation]));
    moves.add(
      GameReportMove(
        ply: i + 1,
        san: move.san,
        uci: move.uci,
        isWhite: move.turn == ChessColor.white,
        classification: classifications[i],
        evaluation: evaluation,
      ),
    );
  }
  return recoverGameReportSummary(
    GameAnalysisReport(
      fingerprint: fingerprint,
      positions: List.unmodifiable(positions),
      moves: List.unmodifiable(moves),
      whiteAccuracy: null,
      blackAccuracy: null,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    whiteRating: whiteRating,
    blackRating: blackRating,
  );
}

/// Fills in the accuracy and estimated ratings of a report that lacks them.
///
/// Both are functions of the per-position scores alone, and a saved PGN keeps
/// every played position's score to the centipawn, so they are recomputed with
/// the same formulas a fresh analysis uses rather than left blank. A report
/// that already has them, or is missing a score, is returned untouched.
GameAnalysisReport recoverGameReportSummary(
  GameAnalysisReport report, {
  int? whiteRating,
  int? blackRating,
}) {
  if (report.whiteAccuracy != null && report.blackAccuracy != null) {
    return report;
  }
  final saved = report.positions;
  if (report.moves.isEmpty || saved.length != report.moves.length + 1) {
    return report;
  }
  if (saved.skip(1).any((position) => !_hasScore(position))) return report;

  // The one score a PGN never carries is the starting position's. Reading it
  // as 0.00 would charge the first move for the whole opening edge, so it
  // takes the first played position's score: the first move loses nothing.
  final start = saved.first;
  final positions = <GameReportPosition>[
    _hasScore(start)
        ? start
        : GameReportPosition(fen: start.fen, lines: [saved[1].bestLine]),
    ...saved.skip(1),
  ];
  final accuracy = computeGameReportAccuracy([
    for (final position in positions)
      gameReportWinPercentage(position.bestLine),
  ]);
  final ratings = computeGameReportEstimatedRatings(
    positions,
    whiteRating: whiteRating,
    blackRating: blackRating,
  );
  return GameAnalysisReport(
    fingerprint: report.fingerprint,
    positions: report.positions,
    moves: report.moves,
    whiteAccuracy: accuracy.white,
    blackAccuracy: accuracy.black,
    whiteEstimatedRating: ratings?.white ?? report.whiteEstimatedRating,
    blackEstimatedRating: ratings?.black ?? report.blackEstimatedRating,
    generatedAt: report.generatedAt,
  );
}

bool _hasScore(GameReportPosition position) =>
    position.bestLine.centipawns != null || position.bestLine.mate != null;

GameReportLine? _savedEvaluation(String? raw) {
  if (raw == null) return null;
  // A PGN may include search depth after the score ("0.32,14"). It does not
  // carry the PV, so leave its line empty rather than inventing one.
  final fields = raw.trim().split(',');
  if (fields.length > 2) return null;
  final depth = fields.length == 2 ? int.tryParse(fields[1].trim()) : 0;
  if (depth == null || depth < 0) return null;
  final score = fields.first.trim();
  if (RegExp(r'^#-?\d+$').hasMatch(score)) {
    final mate = int.tryParse(score.substring(1));
    if (mate == null) return null;
    return GameReportLine(moves: const [], depth: depth, mate: mate);
  }
  if (!RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(score)) return null;
  final pawns = double.tryParse(score);
  if (pawns == null || !pawns.isFinite) return null;
  final centipawns = pawns * 100;
  if (!centipawns.isFinite) return null;
  return GameReportLine(
    moves: const [],
    depth: depth,
    centipawns: centipawns.round(),
  );
}
