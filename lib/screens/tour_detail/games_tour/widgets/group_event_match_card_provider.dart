import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final groupEventMatchCardProvider = AutoDisposeProvider(
  (ref) => _GroupEventMatchCardController(ref),
);

class _GroupEventMatchCardController {
  _GroupEventMatchCardController(this.ref);

  final Ref ref;

  /// Helper to normalize team names for comparison
  String _normalizeTeamName(String name) {
    return name.trim().toLowerCase();
  }
  
  /// Helper to check if two team names match
  bool _teamsMatch(String name1, String name2) {
    return _normalizeTeamName(name1) == _normalizeTeamName(name2);
  }
  
  List<double> getMatchScore({
    required List<MatchWithComparison> matchList,
    required String team,
  }) {
    if (matchList.isEmpty) return [0.0, 0.0];

    double team1 = 0.0; // Header left side
    double team2 = 0.0; // Header right side

    for (final m in matchList) {
      final status = m.game.gameStatus;

      // Ignore live/unknown games
      if (status == GameStatus.ongoing || status == GameStatus.unknown) {
        continue;
      }

      if (status == GameStatus.draw) {
        // Draw: both teams get 0.5
        team1 += 0.5;
        team2 += 0.5;
        continue;
      }

      final same = m.comparison == MatchComparison.sameOrder;
      if (status == GameStatus.whiteWins) {
        // White belongs to header team1 when sameOrder, else to team2
        if (same) {
          team1 += 1.0;
        } else {
          team2 += 1.0;
        }
      } else if (status == GameStatus.blackWins) {
        // Black belongs to header team2 when sameOrder, else to team1
        if (same) {
          team2 += 1.0;
        } else {
          team1 += 1.0;
        }
      }
    }

    return [team1, team2];
  }
}
