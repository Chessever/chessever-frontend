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
    var teamAWon = 0.0;
    var teamBWon = 0.0;
    for (var a = 0; a < matchList.length; a++) {
      if (matchList[a].comparison == MatchComparison.sameOrder) {
        final status = matchList[a].game.gameStatus;
        switch (status) {
          case GameStatus.ongoing:
            break;
          case GameStatus.whiteWins:
            teamAWon = teamAWon + 1;
            break;
          case GameStatus.blackWins:
            teamBWon = teamBWon + 1;
          case GameStatus.draw:
            teamAWon = teamAWon + 0.5;
            teamBWon = teamBWon + 0.5;
          case GameStatus.unknown:
            break;
        }
      } else {
        final status = matchList[a].game.gameStatus;
        switch (status) {
          case GameStatus.ongoing:
            break;
          case GameStatus.whiteWins:
            teamBWon = teamBWon + 1;
            break;
          case GameStatus.blackWins:
            teamAWon = teamAWon + 1;
          case GameStatus.draw:
            teamAWon = teamAWon + 0.5;
            teamBWon = teamBWon + 0.5;
          case GameStatus.unknown:
            break;
        }
      }
    }
    return [teamAWon, teamBWon];
  }
}
