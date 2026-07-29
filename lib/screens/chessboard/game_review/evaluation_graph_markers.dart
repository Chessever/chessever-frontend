import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:flutter/material.dart';

/// One chess.com-style classification marker on the Game Review eval graph.
///
/// [ply] is the graph sample index after the classified move (same X as the
/// path point for that position). [winPercentage] is the Y sample on the same
/// scale as [gameReportWinPercentage].
@immutable
class EvaluationGraphClassificationMarker {
  const EvaluationGraphClassificationMarker({
    required this.ply,
    required this.winPercentage,
    required this.classification,
    required this.color,
  });

  final int ply;
  final double winPercentage;
  final GameMoveClassification classification;
  final Color color;
}

/// Builds drawable classification dots for the eval graph from a report.
///
/// One marker per move with a non-null [GameReportMove.classification], except
/// [GameMoveClassification.bookMove] — book dots crowd the opening of the
/// curve without adding judgment, so they stay off the chart (notation and
/// recap still show book). Move index `i` maps to graph ply `move.ply`
/// (normally `i + 1`) — the position after that move — matching how the
/// active-ply classification keys `activePly - 1`. Colors come from
/// [classificationColor] so graph, board badges, notation chips, and recap
/// counters stay in one palette.
List<EvaluationGraphClassificationMarker>
buildEvaluationGraphClassificationMarkers({
  required List<GameReportMove> moves,
  required List<GameReportPosition> positions,
}) {
  if (positions.isEmpty || moves.isEmpty) {
    return const <EvaluationGraphClassificationMarker>[];
  }

  final markers = <EvaluationGraphClassificationMarker>[];
  for (var i = 0; i < moves.length; i++) {
    final move = moves[i];
    final classification = move.classification;
    if (classification == null) continue;
    // Book is theory, not a quality call — keep it off the curve.
    if (classification == GameMoveClassification.bookMove) continue;

    final ply = move.ply;
    if (ply < 0 || ply >= positions.length) continue;

    markers.add(
      EvaluationGraphClassificationMarker(
        ply: ply,
        winPercentage: gameReportWinPercentage(positions[ply].bestLine),
        classification: classification,
        color: classificationColor(classification),
      ),
    );
  }
  return markers;
}
