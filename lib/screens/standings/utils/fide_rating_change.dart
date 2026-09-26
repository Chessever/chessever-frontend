import 'dart:math' as math;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

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

/// Keep separate FIDE rating lists separate, even inside a single event.
String ratingPoolForGame(GamesTourModel game) {
  // A knockout tour can contain classical games and rapid/blitz tiebreaks.
  // PGN is seconds, unlike human "3+2" labels (minutes). Only parse machine
  // sudden-death controls here; complex/unknown tags retain the source bucket.
  final tag = RegExp(
    r'\[TimeControl "(\d+)(?:\+(\d+))?"\]',
  ).firstMatch(game.pgn ?? '');
  if (tag != null) {
    final seconds =
        int.parse(tag.group(1)!) + 60 * int.parse(tag.group(2) ?? '0');
    if (seconds > 0) {
      if (seconds <= 600) return 'blitz';
      if (seconds < 3600) return 'rapid';
      return 'standard';
    }
  }
  final pool = game.timeControl?.trim().toLowerCase();
  return pool == 'classical' || pool == null || pool.isEmpty
      ? 'standard'
      : pool;
}

/// FIDE's dp conversion table, shared with the Direct server's performanceExpr.
/// A linear interpolation (800 * score / played - 400) is not this table.
int? calculateFidePerformanceRating({
  required List<double> opponentRatings,
  required double score,
}) {
  if (opponentRatings.isEmpty || opponentRatings.any((rating) => rating <= 0)) {
    return null;
  }
  if (score < 0 || score > opponentRatings.length) return null;
  const dp = [
    0,
    7,
    14,
    21,
    29,
    36,
    43,
    50,
    57,
    65,
    72,
    80,
    87,
    95,
    102,
    110,
    117,
    125,
    133,
    141,
    149,
    158,
    166,
    175,
    184,
    193,
    202,
    211,
    220,
    230,
    240,
    251,
    262,
    273,
    284,
    296,
    309,
    322,
    336,
    351,
    366,
    383,
    401,
    422,
    444,
    470,
    501,
    538,
    589,
    677,
    800,
  ];
  final percentage = (100 * score / opponentRatings.length).round();
  final adjustment = dp[(percentage - 50).abs()] * (percentage >= 50 ? 1 : -1);
  final average =
      opponentRatings.reduce((a, b) => a + b) / opponentRatings.length;
  return (average + adjustment).round();
}
