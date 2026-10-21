import 'package:chessever2/repository/supabase/tour/published_tiebreak.dart';
import 'package:chessever2/screens/standings/official_team_feed_link.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';

/// One row in the team-event "Standings" tab: a team's collected score plus its
/// players (the same individual [PlayerStandingModel]s shown on the "Players"
/// tab), revealed when the row is expanded.
class TeamStandingModel {
  final String teamName;
  final int rank;

  /// When set, totals and ordering are the published table after this round.
  final int? officialRound;

  /// Match points — 2 win / 1 draw / 0 loss, counted only for completed
  /// matches. Primary ranking metric (chess team-event standard).
  final num matchPoints;

  /// Board (game) points — sum of finished individual board results. Tiebreak.
  final double gamePoints;

  final int matchesWon;
  final int matchesDrawn;
  final int matchesLost;

  /// Finished boards contributing to [gamePoints]; for display/debug.
  final int boardsPlayed;

  /// Values and priority copied from the organizer, never recomputed.
  final List<PublishedTiebreak> tiebreaks;

  final List<PlayerStandingModel> players;

  /// How an official row's boards are found in the broadcast, whose team
  /// labels can differ from the organizer's spelling. Null for rows built
  /// from the broadcast itself, where [teamName] is the label.
  final OfficialTeamFeedLink? feedLink;

  const TeamStandingModel({
    required this.teamName,
    required this.rank,
    this.officialRound,
    this.tiebreaks = const [],
    required this.matchPoints,
    required this.gamePoints,
    required this.matchesWon,
    required this.matchesDrawn,
    required this.matchesLost,
    required this.boardsPlayed,
    required this.players,
    this.feedLink,
  });

  String get matchPointsLabel => matchPoints % 1 == 0
      ? matchPoints.toInt().toString()
      : matchPoints.toString();

  /// Board points as a decimal, e.g. 26.5 -> "26.5", 31.0 -> "31".
  String get gamePointsLabel => gamePoints % 1 == 0
      ? gamePoints.toInt().toString()
      : gamePoints.toStringAsFixed(1);

  /// [tiebreaks] without the published match-point and game-point columns
  /// (Chess-Results TB1/TB2, Info64 MP/GP) when they repeat the [matchPoints]
  /// and [gamePoints] the row already shows. Derived tiebreaks such as BH:MP
  /// or EMMSB stay.
  ///
  /// Like the hub's parser, only the first Chess-Results column described as
  /// match points (or game points) is the one shown on the card. A later
  /// "Matchpoints (variabel)" column next to a "Matchpoints (2 for wins, …)"
  /// TB1 is a different number, so it stays on every row, including a row
  /// where it happens to equal the match points (0 and 0).
  List<PublishedTiebreak> get extraTiebreaks {
    final matchColumn = tiebreaks.indexWhere(
      (t) => _publishedMatchPoints.hasMatch(t.description),
    );
    final gameColumn = tiebreaks.indexWhere(
      (t) => t.description == 'points (game-points)',
    );
    return [
      for (var i = 0; i < tiebreaks.length; i++)
        if (!_repeatsShownPoints(
          tiebreaks[i],
          isMatchColumn: i == matchColumn,
          isGameColumn: i == gameColumn,
        ))
          tiebreaks[i],
    ];
  }

  bool _repeatsShownPoints(
    PublishedTiebreak tiebreak, {
    required bool isMatchColumn,
    required bool isGameColumn,
  }) {
    final description = tiebreak.description;
    final code = tiebreak.extendedCode;
    if (tiebreak.points == matchPoints &&
        (description == 'MP' || code == 'MP' || isMatchColumn)) {
      return true;
    }
    return tiebreak.points == gamePoints &&
        (description == 'GP' || code == 'GP' || isGameColumn);
  }

  // "Matchpoints (2 for wins, …)" or the organizer's own scale,
  // "Matchpoints (variabel)".
  static final _publishedMatchPoints = RegExp(
    r'^Matchpoints \((\d+ for wins|variabel\))',
  );

  /// "W · D · L" record over completed matches.
  String get recordLabel => '$matchesWon · $matchesDrawn · $matchesLost';

  /// Board points per finished board (GP / boards played). Null when the team
  /// has no finished boards yet.
  double? get averageBoardPoints =>
      boardsPlayed > 0 ? gamePoints / boardsPlayed : null;

  /// Compact average for app bars, e.g. "0.65" or "1" / "—".
  String get averageBoardPointsLabel {
    final avg = averageBoardPoints;
    if (avg == null) return '—';
    if (avg % 1 == 0) return avg.toInt().toString();
    // Two decimals is enough for half-point board averages without noise.
    final fixed = avg.toStringAsFixed(2);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
