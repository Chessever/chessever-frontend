import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final groupEventMatchCardProvider = AutoDisposeProvider(
  (ref) => _GroupEventMatchCardController(ref),
);

class _GroupEventMatchCardController {
  _GroupEventMatchCardController(this.ref);

  final Ref ref;

  List<double> getMatchScore({
    required List<MatchWithComparison> matchList,
    required String team,
  }) {
    return matchScoreForGames(matchList: matchList);
  }
}

/// Board-point split for the matchup header, honouring Lichess `customPoints`.
///
/// Live / unknown boards add nothing — the same rule as a 0–0 before any
/// result, which is what the screenshot's unfinished GCL match should show
/// until a board finishes. A colour-weighted win then adds 3 or 4, not 1.
List<double> matchScoreForGames({
  required List<MatchWithComparison> matchList,
}) {
  if (matchList.isEmpty) return [0.0, 0.0];

  var team1Score = 0.0;
  var team2Score = 0.0;

  for (final m in matchList) {
    final status = m.game.gameStatus;
    final standardWhite = standardResultValueForSide(status, isWhite: true);
    final standardBlack = standardResultValueForSide(status, isWhite: false);
    if (standardWhite == null || standardBlack == null) continue;

    final pts = aggregateBroadcastResultPoints(
      standardWhitePoints: standardWhite,
      standardBlackPoints: standardBlack,
      whiteCustomPoints: m.game.whitePlayer.customPoints,
      blackCustomPoints: m.game.blackPlayer.customPoints,
    );

    if (m.comparison == MatchComparison.oppositeOrder) {
      team1Score += pts.black;
      team2Score += pts.white;
    } else {
      team1Score += pts.white;
      team2Score += pts.black;
    }
  }

  return [team1Score, team2Score];
}
