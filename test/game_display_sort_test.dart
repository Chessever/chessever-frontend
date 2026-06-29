import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sortGameModelsForGamesTab', () {
    test('orders pinned games by board number instead of pin order', () {
      final games = [
        _game('board-30', boardNr: 30),
        _game('board-20', boardNr: 20),
        _game('board-1', boardNr: 1),
        _game('board-10', boardNr: 10),
        _game('board-3', boardNr: 3),
      ];

      final sorted = sortGameModelsForGamesTab(
        games: games,
        pinnedIds: const ['board-20', 'board-10', 'board-3'],
      );

      expect(sorted.map((game) => game.gameId).toList(), [
        'board-3',
        'board-10',
        'board-20',
        'board-1',
        'board-30',
      ]);
    });

    test('puts live games above completed games before round ordering', () {
      final games = [
        _game(
          'completed-newer-round',
          boardNr: 1,
          roundSlug: 'round-8',
          status: GameStatus.whiteWins,
        ),
        _game('live-older-round', boardNr: 2, roundSlug: 'round-7'),
      ];

      final sorted = sortGameModelsForGamesTab(
        games: games,
        pinnedIds: const [],
      );

      expect(sorted.map((game) => game.gameId).toList(), [
        'live-older-round',
        'completed-newer-round',
      ]);
    });
  });
}

GamesTourModel _game(
  String id, {
  required int boardNr,
  String roundSlug = 'round-1',
  GameStatus status = GameStatus.ongoing,
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player('White $id'),
    blackPlayer: _player('Black $id'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: status,
    boardNr: boardNr,
    roundId: 'round-1',
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
