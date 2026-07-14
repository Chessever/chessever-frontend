import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tournament Games tab card order', () {
    test('uses board_nr before the non-authoritative game slug number', () {
      final sorted = sortTournamentRoundGamesByBoard(<GamesTourModel>[
        _game('board-2', boardNr: 2, roundSlug: 'round-8--game-99'),
        _game('board-1', boardNr: 1, roundSlug: 'round-8--game-1'),
      ]);

      expect(sorted.map((game) => game.gameId), <String>['board-1', 'board-2']);
    });

    test('orders null and tied boards by a deterministic fallback', () {
      final sorted = sortTournamentRoundGamesByBoard(<GamesTourModel>[
        _game('null-z', boardNr: null, roundSlug: 'round-8--game-2'),
        _game('tie-z', boardNr: 7, roundSlug: 'round-8--game-2'),
        _game('null-a', boardNr: null, roundSlug: 'round-8--game-2'),
        _game('tie-a', boardNr: 7, roundSlug: 'round-8--game-2'),
      ]);

      expect(sorted.map((game) => game.gameId), <String>[
        'tie-a',
        'tie-z',
        'null-a',
        'null-z',
      ]);
    });
  });
}

GamesTourModel _game(
  String id, {
  required int? boardNr,
  required String roundSlug,
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player('White $id'),
    blackPlayer: _player('Black $id'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    boardNr: boardNr,
    roundId: 'round-8',
    roundSlug: roundSlug,
    tourId: 'tour-1',
  );
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: 'GM',
    rating: 2700,
    countryCode: 'USA',
    team: null,
  );
}
