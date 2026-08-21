import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
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
    test('event player games keep their filtered board navigation list', () {
      final context = scoreCardGameNavigationContext(hasEventContext: true);
      expect(context.viewSource, ChessboardView.tour);
      expect(context.listPolicy, BoardNavigationListPolicy.preserve);
    });

    test('global player games keep their filtered board navigation list', () {
      final context = scoreCardGameNavigationContext(hasEventContext: false);
      expect(context.viewSource, ChessboardView.favScorecard);
      expect(context.listPolicy, BoardNavigationListPolicy.preserve);
    });

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

    test('opponent tap reuses the event standings entry', () {
      final players = [
        player(name: 'Pourkashiyan, Atousa', fideId: 12501049),
        player(name: 'Displayed Differently', fideId: 2012782),
      ];

      final target = scoreCardOpponentTarget(
        players: players,
        name: 'Yip, Carissa',
        fideId: 2012782,
        countryCode: 'USA',
        title: 'GM',
        rating: 2504,
      );

      expect(target, same(players[1]));
    });

    test('opponent tap falls back to the game row when off the standings', () {
      final target = scoreCardOpponentTarget(
        players: const [],
        name: 'Pourkashiyan, Atousa',
        fideId: 12501049,
        gamebasePlayerId: 'player-42',
        countryCode: 'USA',
        title: 'WGM',
        rating: 2308,
        team: 'Team A',
      );

      expect(target.name, 'Pourkashiyan, Atousa');
      expect(target.fideId, 12501049);
      expect(target.gamebasePlayerId, 'player-42');
      expect(target.countryCode, 'USA');
      expect(target.title, 'WGM');
      expect(target.score, 2308);
      expect(target.team, 'Team A');
    });

    test('opponent tap matches on name when no fide id is available', () {
      final players = [player(name: 'Carlsen, Magnus')];

      final target = scoreCardOpponentTarget(
        players: players,
        name: '  carlsen, magnus ',
        countryCode: 'NOR',
        title: 'GM',
        rating: 2839,
      );

      expect(target, same(players.first));
    });
  });
}
