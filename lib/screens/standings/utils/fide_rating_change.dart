import 'dart:math' as math;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart';

const scorecardRatingPools = {
  'standard': 'Classical',
  'rapid': 'Rapid',
  'blitz': 'Blitz',
};

typedef ScorecardFormatStats = ({
  int? performance,
  int? ratingDiff,
  double score,
  int totalGames,
});
typedef ScorecardRatedResult = ({
  double opponentRating,
  double score,
  double? ratingChange,
});

final _unplayedTermination = RegExp(
  r'\[Termination\s+"[^"]*\b(?:forfeit|unplayed|walkover|abandoned)\b[^"]*"\]',
  caseSensitive: false,
);
final _playedMove = RegExp(r'(?:^|\s)1\s*\.{1,3}\s*(?:[a-hKQRBN]|[O0]-[O0])');

/// Armageddon has no Classical, Rapid, or Blitz scorecard filter.
String? scorecardFormatForGame(
  GamesTourModel game, {
  String? roundName,
  String? stageName,
}) {
  if (isArmageddonGame(game) ||
      (roundName?.toLowerCase().contains('armageddon') ?? false)) {
    return null;
  }
  final pool = ratingPoolForGame(
    game,
    roundName: roundName,
    stageName: stageName,
  );
  return scorecardRatingPools.containsKey(pool) ? pool : null;
}

bool isScorecardRatedGame(GamesTourModel game) {
  if (!game.gameStatus.isFinished ||
      game.isDoubleForfeit ||
      isArmageddonGame(game)) {
    return false;
  }
  final pgn = game.pgn ?? '';
  if (_unplayedTermination.hasMatch(pgn)) return false;
  // Don't turn a published result with no moves into an Elo change.
  final board = game.fen?.trim().split(' ').first;
  return game.hasStarted ||
      _playedMove.hasMatch(pgn) ||
      (board != null &&
          board.isNotEmpty &&
          board != 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR' &&
          !pgn.contains('[SetUp "1"]'));
}

ScorecardFormatStats summarizeScorecardFormat(
  List<ScorecardRatedResult> games,
) {
  final score = games.fold(0.0, (sum, game) => sum + game.score);
  return (
    score: score,
    totalGames: games.length,
    performance: calculateFidePerformanceRating(
      opponentRatings: [for (final game in games) game.opponentRating],
      score: score,
    ),
    ratingDiff: games.isEmpty || games.any((game) => game.ratingChange == null)
        ? null
        : games.fold(0.0, (sum, game) => sum + game.ratingChange!).round(),
  );
}

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
  final ratingDiff = (opponentRating - playerRating)
      .clamp(-400, 400)
      .toDouble();
  final expectedScore = 1 / (1 + math.pow(10, ratingDiff / 400.0));
  final resolvedKFactor = kFactor ?? fideKFactorForSelectedRating(playerRating);
  return resolvedKFactor * (actualScore - expectedScore);
}

final _namedRatingFormat = RegExp(
  r'\b(blitz|rapid|fast[\s_-]+classic(?:al)?|classical)\b',
  caseSensitive: false,
);

String? _namedPool(String? label) {
  final pools = {
    for (final match in _namedRatingFormat.allMatches(label ?? ''))
      switch (match.group(1)!.toLowerCase()) {
        'blitz' => 'blitz',
        'rapid' => 'rapid',
        _ => 'standard',
      },
  };
  return pools.length == 1 ? pools.single : null;
}

/// Keep separate FIDE rating lists separate, even inside a single event.
String ratingPoolForGame(
  GamesTourModel game, {
  String? roundName,
  String? stageName,
}) {
  // Mixed-format broadcasts can give every board the enclosing event's
  // default pool. The explicit round format also distinguishes Fast Classic
  // from a rapid game with a similarly short first time-control period.
  final namedPool =
      _namedPool(roundName) ?? _namedPool(game.roundSlug?.replaceAll('_', '-'));
  if (namedPool != null) return namedPool;
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
  final pool = _namedPool(stageName) ?? game.timeControl?.trim().toLowerCase();
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
