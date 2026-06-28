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

    test('finish filter keeps only games ending by selected move', () {
      final shortGame = _game(
        status: GameStatus.whiteWins,
        pgn: '1. e4 e5 2. Nf3 Nc6 15. Qxf7# 1-0',
      );
      final longGame = _game(
        status: GameStatus.blackWins,
        pgn: '1. d4 Nf6 2. c4 e6 26. Qb3 Be7 0-1',
      );

      final filtered = GameFilterHelper.applyFilter([
        shortGame,
        longGame,
      ], GameFilter(finish: GameFinishFilter.byMove20));

      expect(filtered, [shortGame]);
    });
  });
}

GamesTourModel _game({
  required GameStatus status,
  DateTime? lastMoveTime,
  DateTime? gameDay,
  String? lastMove,
  String? pgn,
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
    pgn: pgn,
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
