/// Convert evaluation to white's perspective so evaluation bars stay consistent.
///
/// WARNING: Only use for RAW Stockfish output!
/// DO NOT use for evaluations from Lichess or Supabase - they are already normalized!
///
/// Stockfish returns scores from the side to move. When the side to move is
/// black, the value must be flipped so positive numbers always favour white.
/// Any parsing errors simply fall back to the original value.
///
/// USAGE:
/// - Cascade provider (Lichess/Supabase): DO NOT use this (already normalized)
/// - Raw Stockfish evaluation: USE this to normalize
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
