import 'package:chessever2/screens/player_profile/utils/player_game_recency.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerCard _player(String name) => PlayerCard(
  name: name,
  federation: '',
  title: '',
  rating: 2500,
  countryCode: '',
  team: null,
);

GamesTourModel _game({
  required String id,
  required DateTime date,
  required String round,
}) => GamesTourModel(
  gameId: id,
  source: GameSource.twic,
  whitePlayer: _player('White'),
  blackPlayer: _player('Black'),
  whiteTimeDisplay: '--:--',
  blackTimeDisplay: '--:--',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.draw,
  roundId: round,
  roundSlug: round,
  tourId: 'event',
  lastMoveTime: date,
);

void main() {
  group('player profile game recency', () {
    test('shows the latest round first when event games share a date', () {
      final date = DateTime.utc(2026, 8, 22);
      final games = <GamesTourModel>[
        _game(id: 'round-1', date: date, round: '1'),
        _game(id: 'round-3', date: date, round: 'Round 3'),
        _game(id: 'round-6', date: date, round: '6'),
      ];

      games.sort(comparePlayerProfileGamesNewestFirst);

      expect(games.map((game) => game.gameId), [
        'round-6',
        'round-3',
        'round-1',
      ]);
    });

    test('newer game date remains more important than round number', () {
      final games = <GamesTourModel>[
        _game(id: 'older-round-9', date: DateTime.utc(2026, 8, 21), round: '9'),
        _game(id: 'newer-round-1', date: DateTime.utc(2026, 8, 22), round: '1'),
      ];

      games.sort(comparePlayerProfileGamesNewestFirst);

      expect(games.map((game) => game.gameId), [
        'newer-round-1',
        'older-round-9',
      ]);
    });

    test('preserves the Gamebase round field used for ordering', () {
      expect(
        playerProfileRoundLabel(<String, dynamic>{
          'round': '6',
        }, fallback: 'C42'),
        '6',
      );
      expect(
        playerProfileRoundLabel(<String, dynamic>{
          'round': '  ',
        }, fallback: 'C42'),
        'C42',
      );
    });
  });
}
