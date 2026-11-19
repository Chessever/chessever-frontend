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

  group('A game in play by its own row (the Live first fallback)', () {
    final now = DateTime.utc(2026, 5, 23, 12);
    // How a row with no last_move_time arrives: its game day, parsed as a
    // local midnight, stands in for the last move (GamesTourModel.fromGame).
    final gameDay = DateTime(2026, 5, 23);

    test('a 0-move shell of today is never in play, in any time zone', () {
      final shell = _game(
        status: GameStatus.ongoing,
        gameDay: gameDay,
        lastMoveTime: gameDay,
      );
      expect(GameFilterHelper.isInPlay(shell, now: now), isFalse);
    });

    test('a game with a move but no time on its row is in play on its day, '
        'in any time zone', () {
      final moved = _game(
        status: GameStatus.ongoing,
        gameDay: gameDay,
        lastMoveTime: gameDay,
        lastMove: 'e2e4',
      );
      expect(GameFilterHelper.isInPlay(moved, now: now), isTrue);
      expect(
        GameFilterHelper.isInPlay(moved, now: DateTime.utc(2026, 5, 24, 12)),
        isFalse,
      );
    });

    test('a game with a move today is in play', () {
      final game = _game(
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 5, 23, 11, 40),
        lastMove: 'e2e4',
      );
      expect(GameFilterHelper.isInPlay(game, now: now), isTrue);
    });

    test('a game still in play past UTC midnight stays in play for the '
        'carry, a leftover `*` does not', () {
      final justAfterMidnight = DateTime.utc(2026, 5, 24, 0, 30);
      final playing = _game(
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 5, 23, 23, 10),
        lastMove: 'e2e4',
      );
      final leftover = _game(
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 5, 23, 15),
        lastMove: 'e2e4',
      );
      expect(
        GameFilterHelper.isLiveNow(playing, now: justAfterMidnight),
        isFalse,
      );
      expect(
        GameFilterHelper.isInPlay(playing, now: justAfterMidnight),
        isTrue,
      );
      expect(
        GameFilterHelper.isInPlay(leftover, now: justAfterMidnight),
        isFalse,
      );
    });

    test('a finished game is never in play', () {
      final game = _game(
        status: GameStatus.whiteWins,
        lastMoveTime: DateTime.utc(2026, 5, 23, 11, 40),
        lastMove: 'e2e4',
      );
      expect(GameFilterHelper.isInPlay(game, now: now), isFalse);
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
