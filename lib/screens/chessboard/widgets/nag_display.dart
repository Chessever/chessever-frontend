import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter/material.dart';

enum NagCategory {
  /// Move quality glyphs ($1–$6, $7): bold colored, eye-catching.
  quality,

  /// Position assessment glyphs (=, ±, ∓, ∞, ⩲, ⩱, +-, -+, etc).
  /// Always rendered in muted slate so they don't compete with quality glyphs.
  evaluation,

  /// Observation glyphs (novelty, idea, counterplay, etc).
  observation,
}

class NagDisplay {
  final String symbol;
  final Color color;
  final NagCategory category;

  const NagDisplay(this.symbol, this.color, this.category);

  bool get isQuality => category == NagCategory.quality;
}

const Color _kEvalSlate = Color(0xFF9AA3AD);
const Color _kObservationDim = Color(0xFFB8C4D0);

// Quality NAG colors resolve through [moveAnnotationColor] so text glyphs
// match the classification badge SVG gradient tops (board, notation, recap).
NagDisplay? getNagDisplay(int nag) {
  switch (nag) {
    case 1:
      // goodMove — navy !
      return NagDisplay(
        '!',
        moveAnnotationColor(LichessMoveAnnotationType.goodMove),
        NagCategory.quality,
      );
    case 2:
      // mistake — dark red ?
      return NagDisplay(
        '?',
        moveAnnotationColor(LichessMoveAnnotationType.mistake),
        NagCategory.quality,
      );
    case 3:
      // brilliant — cyan !!
      return NagDisplay(
        '!!',
        moveAnnotationColor(LichessMoveAnnotationType.brilliant),
        NagCategory.quality,
      );
    case 4:
      // blunder — bright red ??
      return NagDisplay(
        '??',
        moveAnnotationColor(LichessMoveAnnotationType.blunder),
        NagCategory.quality,
      );
    case 5:
      // No classification badge equivalent — keep the canonical
      // "speculative" magenta.
      return const NagDisplay('!?', Color(0xFFEA45D8), NagCategory.quality);
    case 6:
      // inaccuracy — brown/orange ?!
      return NagDisplay(
        '?!',
        moveAnnotationColor(LichessMoveAnnotationType.inaccuracy),
        NagCategory.quality,
      );
    case 7:
      // only-move / forced
      return NagDisplay(
        '□',
        moveAnnotationColor(LichessMoveAnnotationType.forced),
        NagCategory.quality,
      );
    case 10:
      return const NagDisplay('=', _kEvalSlate, NagCategory.evaluation);
    case 13:
      return const NagDisplay('∞', _kEvalSlate, NagCategory.evaluation);
    case 14:
      return const NagDisplay('⩲', _kEvalSlate, NagCategory.evaluation);
    case 15:
      return const NagDisplay('⩱', _kEvalSlate, NagCategory.evaluation);
    case 16:
      return const NagDisplay('±', _kEvalSlate, NagCategory.evaluation);
    case 17:
      return const NagDisplay('∓', _kEvalSlate, NagCategory.evaluation);
    case 18:
      return const NagDisplay('+−', _kEvalSlate, NagCategory.evaluation);
    case 19:
      return const NagDisplay('−+', _kEvalSlate, NagCategory.evaluation);
    case 22:
    case 23:
      return const NagDisplay('⨀', _kEvalSlate, NagCategory.evaluation);
    case 32:
      return const NagDisplay('⟳', _kObservationDim, NagCategory.observation);
    case 36:
      return const NagDisplay('→', _kObservationDim, NagCategory.observation);
    case 40:
      return const NagDisplay('↑', _kObservationDim, NagCategory.observation);
    case 44:
      return const NagDisplay('=∞', _kEvalSlate, NagCategory.evaluation);
    case 132:
      return const NagDisplay('⇆', _kObservationDim, NagCategory.observation);
    case 138:
      return const NagDisplay('⊕', _kObservationDim, NagCategory.observation);
    case 140:
      return const NagDisplay('∆', _kObservationDim, NagCategory.observation);
    case 146:
      return const NagDisplay('N', _kObservationDim, NagCategory.observation);
    default:
      return null;
  }
}

/// Convenience: the NAG most worth surfacing on the board, in priority order.
/// Quality NAGs win over evaluation/observation; lower codes win within a tier.
int? primaryBoardNag(List<int>? nags) {
  if (nags == null || nags.isEmpty) return null;
  int? best;
  int bestRank = 99;
  for (final nag in nags) {
    final d = getNagDisplay(nag);
    if (d == null) continue;
    final rank = switch (d.category) {
      NagCategory.quality => 0,
      NagCategory.evaluation => 1,
      NagCategory.observation => 2,
    };
    if (rank < bestRank) {
      bestRank = rank;
      best = nag;
    }
  }
  return best;
}
