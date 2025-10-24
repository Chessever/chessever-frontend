import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
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
    if (matchList.isEmpty) return [0.0, 0.0];

    double team1Score = 0.0; // Left side of header
    double team2Score = 0.0; // Right side of header

    for (final m in matchList) {
      final status = m.game.gameStatus;

      // Ignore live/unknown games
      if (status == GameStatus.ongoing || status == GameStatus.unknown) {
        continue;
      }

      if (status == GameStatus.draw) {
        team1Score += 0.5;
        team2Score += 0.5;
        continue;
      }

      // Use comparison to determine which team is on which side
      // sameOrder: white=team1(left), black=team2(right)
      // oppositeOrder: black=team1(left), white=team2(right)
      final isSameOrder = m.comparison == MatchComparison.sameOrder;

      if (status == GameStatus.whiteWins) {
        if (isSameOrder) {
          team1Score += 1.0; // White is on left side
        } else {
          team2Score += 1.0; // White is on right side
        }
      } else if (status == GameStatus.blackWins) {
        if (isSameOrder) {
          team2Score += 1.0; // Black is on right side
        } else {
          team1Score += 1.0; // Black is on left side
        }
      }
    }

    return [team1Score, team2Score];
  }
}
