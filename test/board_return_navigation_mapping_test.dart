import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a reordered expanded-board result back to the caller index', () {
    final callerGames = [
      _game('caller-a'),
      _game('caller-b'),
      _game('caller-c'),
    ];
    final boardGames = [
      _game('expanded-only'),
      _game('caller-c'),
      _game('caller-a'),
      _game('caller-b'),
    ];

    expect(
      callerIndexForBoardReturn(
        callerGames: callerGames,
        boardGames: boardGames,
        boardIndex: 1,
      ),
      2,
    );
  });

  test('does not map a game that exists only in the expanded board list', () {
    final callerGames = [_game('caller-a'), _game('caller-b')];
    final boardGames = [
      _game('caller-b'),
      _game('expanded-only'),
      _game('caller-a'),
    ];

    expect(
      callerIndexForBoardReturn(
        callerGames: callerGames,
        boardGames: boardGames,
        boardIndex: 1,
      ),
      isNull,
    );
  });
}

GamesTourModel _game(String id) {
  final player = PlayerCard(
    name: 'Player',
    federation: 'USA',
    title: 'GM',
    rating: 2700,
    countryCode: 'USA',
    team: null,
  );
  return GamesTourModel(
    gameId: id,
    whitePlayer: player,
    blackPlayer: player,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.unknown,
    roundId: 'round-1',
    tourId: 'tour-1',
  );
}
