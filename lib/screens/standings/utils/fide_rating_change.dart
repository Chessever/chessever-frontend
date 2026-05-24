import 'dart:math' as math;

/// Returns the simple FIDE K-factor fallback for the rating selected by the
/// event's time-control bucket.
///
/// The caller must pass the rating that is actually used for the calculation
/// (standard/classical rating for standard events, rapid rating for rapid
/// events, blitz rating for blitz events). If that selected rating is 2400 or
/// higher, FIDE uses K=10 for that rating bucket.
int fideKFactorForSelectedRating(num selectedRating) {
  return selectedRating >= 2400 ? 10 : 20;
}

/// Calculates a single-game FIDE Elo rating change using ChessEver's current
/// simple fallback K-factor rule.
double calculateFideRatingChange({
  required num playerRating,
  required num opponentRating,
  required double actualScore,
}) {
  final ratingDiff =
      (opponentRating - playerRating).clamp(-400, 400).toDouble();
  final expectedScore = 1 / (1 + math.pow(10, ratingDiff / 400.0));
  final kFactor = fideKFactorForSelectedRating(playerRating);
  return kFactor * (actualScore - expectedScore);
}
