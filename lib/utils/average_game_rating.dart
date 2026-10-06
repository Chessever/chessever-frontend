const int missingGameRatingFallback = 1800;

/// Average used to rank game cards. Each unrated player contributes the same
/// fallback, and half-point averages round up, matching Miniatures.
int effectiveAverageGameRating(int? whiteRating, int? blackRating) {
  final white = whiteRating != null && whiteRating > 0
      ? whiteRating
      : missingGameRatingFallback;
  final black = blackRating != null && blackRating > 0
      ? blackRating
      : missingGameRatingFallback;
  return ((white + black) / 2).round();
}
