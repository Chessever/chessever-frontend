import 'dart:math' as math;

/// Simple FIDE K-factor fallback for the rating selected by the event's
/// time-control bucket.
///
/// The caller must pass the rating that is actually used for the calculation:
/// standard/classical for standard events, rapid for rapid events, and blitz
/// for blitz events. If that selected rating is 2400 or higher, use K=10.
int fideKFactorForSelectedRating(num selectedRating) {
  return selectedRating >= 2400 ? 10 : 20;
}

/// Scorecard fallback K-factor used only when FIDE's published K value is not
/// available from `chess_players`.
int scoreCardFallbackKFactorForSelectedRating(
  num selectedRating, {
  String? title,
  String? timeControl,
}) {
  if (selectedRating >= 2400) {
    return fideKFactorForSelectedRating(selectedRating);
  }

  final tc = timeControl?.toLowerCase();
  if (tc == 'rapid' || tc == 'blitz') {
    return 20;
  }

  if (title != null) {
    final normalizedTitle = title.toUpperCase();
    if (normalizedTitle == 'GM' || normalizedTitle == 'IM') {
      return 10;
    }
  }

  return fideKFactorForSelectedRating(selectedRating);
}

double calculateFideRatingChange({
  required num playerRating,
  required num opponentRating,
  required double actualScore,
  int? kFactor,
}) {
  final ratingDiff =
      (opponentRating - playerRating).clamp(-400, 400).toDouble();
  final expectedScore = 1 / (1 + math.pow(10, ratingDiff / 400.0));
  final resolvedKFactor = kFactor ?? fideKFactorForSelectedRating(playerRating);
  return resolvedKFactor * (actualScore - expectedScore);
}
