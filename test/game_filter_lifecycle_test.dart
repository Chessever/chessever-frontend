import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameFilterHelper lifecycle filters', () {
    test('does not treat stale ongoing games as live', () {
      final now = DateTime.utc(2026, 5, 23, 12);
      final staleGame = _game(
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 3, 1, 14),
        lastMove: 'e4',
      );

      expect(GameFilterHelper.isLiveNow(staleGame, now: now), isFalse);
    });

    test('treats current-day ongoing games as live', () {
      final now = DateTime.utc(2026, 5, 23, 12);
      final liveGame = _game(
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 5, 23, 11),
        lastMove: 'e4',
      );

      expect(GameFilterHelper.isLiveNow(liveGame, now: now), isTrue);
    });

    test('completed filter excludes stale ongoing and unknown games', () {
      final games = [
        _game(status: GameStatus.ongoing, gameDay: DateTime.utc(2026, 3, 1)),
        _game(status: GameStatus.unknown, gameDay: DateTime.utc(2026, 3, 1)),
        _game(status: GameStatus.whiteWins, gameDay: DateTime.utc(2026, 3, 1)),
      ];

      final filtered = GameFilterHelper.applyFilter(
        games,
        GameFilter(live: GameLiveFilter.completed),
      );

      expect(filtered.map((game) => game.gameStatus), [GameStatus.whiteWins]);
    });
  });
}

GamesTourModel _game({
  required GameStatus status,
  DateTime? lastMoveTime,
  DateTime? gameDay,
  String? lastMove,
}) {
  return GamesTourModel(
    gameId: '${status.name}-${lastMoveTime ?? gameDay}',
    whitePlayer: _player('White'),
    blackPlayer: _player('Black'),
    whiteTimeDisplay: '10:00',
    blackTimeDisplay: '10:00',
    whiteClockCentiseconds: 60000,
    blackClockCentiseconds: 60000,
    whiteClockSeconds: 600,
    blackClockSeconds: 600,
    gameStatus: status,
    roundId: 'round-1',
    tourId: 'tour-1',
    lastMoveTime: lastMoveTime,
    gameDay: gameDay,
    lastMove: lastMove,
  );
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: '',
    rating: 2500,
    countryCode: 'USA',
    team: null,
  );
}
