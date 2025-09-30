/// Get evaluation with consistent perspective for evaluation bar display
/// Option 1: Always from white's perspective (consistent colors)
/// Option 2: From current player's perspective (intuitive for current player)
double getConsistentEvaluation(double evaluation, String fen) {
  // Convert all evaluations to white's perspective for consistent bar colors
  // Stockfish returns evaluations from current player's perspective, so we need to flip
  // when it's black's turn to maintain consistency with Lichess (which we already converted)

  try {
    final fenParts = fen.split(' ');
    if (fenParts.length >= 2 && fenParts[1] == 'b') {
      // Black to move: flip the evaluation to white's perspective
      return -evaluation;
    }
  } catch (e) {
    print('Error parsing FEN for perspective: $e');
  }

  return evaluation; // White to move: already in white's perspective
}
