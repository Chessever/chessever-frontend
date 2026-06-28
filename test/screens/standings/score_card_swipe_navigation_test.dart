import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PlayerStandingModel player({
    required String name,
    int? fideId,
    String? gamebasePlayerId,
  }) {
    return PlayerStandingModel(
      countryCode: 'AZE',
      name: name,
      score: 2500,
      scoreChange: 0,
      matchScore: '0 / 0',
      fideId: fideId,
      gamebasePlayerId: gamebasePlayerId,
    );
  }

  group('score card swipe navigation', () {
    test('selects adjacent players in standings order', () {
      final players = [
        player(name: 'First, Player', fideId: 1),
        player(name: 'Second, Player', fideId: 2),
        player(name: 'Third, Player', fideId: 3),
      ];

      expect(
        adjacentScoreCardPlayerForSwipe(
          players: players,
          selectedPlayer: players[1],
          direction: ScoreCardSwipeDirection.previous,
        ),
        players[0],
      );
      expect(
        adjacentScoreCardPlayerForSwipe(
          players: players,
          selectedPlayer: players[1],
          direction: ScoreCardSwipeDirection.next,
        ),
        players[2],
      );
    });

    test('does not wrap past the first or last player', () {
      final players = [
        player(name: 'First, Player', fideId: 1),
        player(name: 'Second, Player', fideId: 2),
      ];

      expect(
        adjacentScoreCardPlayerForSwipe(
          players: players,
          selectedPlayer: players.first,
          direction: ScoreCardSwipeDirection.previous,
        ),
        isNull,
      );
      expect(
        adjacentScoreCardPlayerForSwipe(
          players: players,
          selectedPlayer: players.last,
          direction: ScoreCardSwipeDirection.next,
        ),
        isNull,
      );
    });

    test('matches equivalent selected player by fide id before name', () {
      final players = [
        player(name: 'Displayed, Name', fideId: 42),
        player(name: 'Other, Player', fideId: 43),
      ];
      final selected = player(name: 'Slightly Different, Name', fideId: 42);

      expect(findScoreCardPlayerIndex(players, selected), 0);
    });
  });
}
