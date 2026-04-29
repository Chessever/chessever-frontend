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

// Quality NAG colors mirror LichessMoveAnnotationTypeX.color in
// chess_board_screen_new.dart so glyphs render identically whether they
// come from the PGN ($N), the user's Annotate sheet, or a Lichess fetched
// analysis classification (good/inaccuracy/mistake/blunder/brilliant).
NagDisplay? getNagDisplay(int nag) {
  switch (nag) {
    case 1:
      // Lichess goodMove
      return const NagDisplay('!', Color(0xFF177A68), NagCategory.quality);
    case 2:
      // Lichess mistake
      return const NagDisplay('?', Color(0xFFEB9518), NagCategory.quality);
    case 3:
      // Lichess brilliant
      return const NagDisplay('!!', Color(0xFF177A68), NagCategory.quality);
    case 4:
      // Lichess blunder
      return const NagDisplay('??', Color(0xFFC9342E), NagCategory.quality);
    case 5:
      // No Lichess equivalent — keep the canonical "speculative" magenta.
      return const NagDisplay('!?', Color(0xFFEA45D8), NagCategory.quality);
    case 6:
      // Lichess inaccuracy (matches the yellow rendered for $6 when the
      // game is fetched from Lichess analysis).
      return const NagDisplay('?!', Color(0xFFFABE46), NagCategory.quality);
    case 7:
      return const NagDisplay('□', Color(0xFFA04048), NagCategory.quality);
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
