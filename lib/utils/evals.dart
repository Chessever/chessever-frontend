/// Convert evaluation to white's perspective so evaluation bars stay consistent.
///
/// Stockfish returns scores from the side to move. When the side to move is
/// black, the value must be flipped so positive numbers always favour white.
/// Any parsing errors simply fall back to the original value.
double getConsistentEvaluation(double evaluation, String fen) {
  try {
    final parts = fen.split(' ');
    if (parts.length >= 2 && parts[1] == 'b') {
      return -evaluation;
    }
  } catch (_) {
    // ignore and return incoming evaluation
  }
  return evaluation;
}
