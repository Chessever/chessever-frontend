import 'package:chessever2/screens/standings/player_standing_model.dart';

/// One row in the team-event "Standings" tab: a team's collected score plus its
/// players (the same individual [PlayerStandingModel]s shown on the "Players"
/// tab), revealed when the row is expanded.
class TeamStandingModel {
  final String teamName;
  final int rank;

  /// Match points — 2 win / 1 draw / 0 loss, counted only for completed
  /// matches. Primary ranking metric (chess team-event standard).
  final int matchPoints;

  /// Board (game) points — sum of finished individual board results. Tiebreak.
  final double gamePoints;

  final int matchesWon;
  final int matchesDrawn;
  final int matchesLost;

  /// Finished boards contributing to [gamePoints]; for display/debug.
  final int boardsPlayed;

  final List<PlayerStandingModel> players;

  const TeamStandingModel({
    required this.teamName,
    required this.rank,
    required this.matchPoints,
    required this.gamePoints,
    required this.matchesWon,
    required this.matchesDrawn,
    required this.matchesLost,
    required this.boardsPlayed,
    required this.players,
  });

  /// Board points as a decimal, e.g. 26.5 -> "26.5", 31.0 -> "31".
  String get gamePointsLabel =>
      gamePoints % 1 == 0
          ? gamePoints.toInt().toString()
          : gamePoints.toStringAsFixed(1);

  /// "W · D · L" record over completed matches.
  String get recordLabel => '$matchesWon · $matchesDrawn · $matchesLost';
}
