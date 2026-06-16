import 'package:chessever2/screens/chessboard/utils/chess_board_teaching_eligibility.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldShowChessBoardTeachingsForGame', () {
    test('allows current-day Supabase live games', () {
      final now = DateTime.utc(2026, 6, 15, 12);
      final game = _game(
        source: GameSource.supabase,
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 6, 15, 11),
      );

      expect(shouldShowChessBoardTeachingsForGame(game, now: now), isTrue);
    });

    test('blocks finished Supabase games', () {
      final now = DateTime.utc(2026, 6, 15, 12);
      final game = _game(
        source: GameSource.supabase,
        status: GameStatus.whiteWins,
        lastMoveTime: DateTime.utc(2026, 6, 15, 11),
      );

      expect(shouldShowChessBoardTeachingsForGame(game, now: now), isFalse);
    });

    test('blocks board editor analysis positions', () {
      final now = DateTime.utc(2026, 6, 15, 12);
      final game = _game(
        source: GameSource.boardEditor,
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 6, 15, 11),
      );

      expect(shouldShowChessBoardTeachingsForGame(game, now: now), isFalse);
    });

    test('blocks offline gamebase-style ongoing games', () {
      final now = DateTime.utc(2026, 6, 15, 12);
      final game = _game(
        source: GameSource.gamebase,
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 6, 15, 11),
      );

      expect(shouldShowChessBoardTeachingsForGame(game, now: now), isFalse);
    });
  });
}

GamesTourModel _game({
  required GameSource source,
  required GameStatus status,
  DateTime? lastMoveTime,
}) {
  return GamesTourModel(
    gameId: '${source.name}-${status.name}',
    source: source,
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
    lastMove: lastMoveTime == null ? null : 'e2e4',
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
