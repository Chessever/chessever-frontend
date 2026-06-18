import 'package:chessever2/screens/chessboard/utils/chess_board_teaching_eligibility.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldShowChessBoardTeachingsForGame', () {
    test('allows Supabase live games', () {
      final game = _game(
        source: GameSource.supabase,
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 6, 15, 11),
      );

      expect(shouldShowChessBoardTeachingsForGame(game), isTrue);
    });

    test('allows finished Supabase games', () {
      final game = _game(
        source: GameSource.supabase,
        status: GameStatus.whiteWins,
        lastMoveTime: DateTime.utc(2026, 6, 15, 11),
      );

      expect(shouldShowChessBoardTeachingsForGame(game), isTrue);
    });

    test('allows gamebase games', () {
      final game = _game(
        source: GameSource.gamebase,
        status: GameStatus.blackWins,
      );

      expect(shouldShowChessBoardTeachingsForGame(game), isTrue);
    });

    test('allows TWIC games', () {
      final game = _game(source: GameSource.twic, status: GameStatus.draw);

      expect(shouldShowChessBoardTeachingsForGame(game), isTrue);
    });

    test('allows saved analysis games', () {
      final game = _game(
        source: GameSource.savedAnalysis,
        status: GameStatus.whiteWins,
      );

      expect(shouldShowChessBoardTeachingsForGame(game), isTrue);
    });

    test('blocks board editor analysis positions', () {
      final game = _game(
        source: GameSource.boardEditor,
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 6, 15, 11),
      );

      expect(shouldShowChessBoardTeachingsForGame(game), isFalse);
    });

    test('blocks opening explorer analysis positions', () {
      final game = _game(
        source: GameSource.openingExplorer,
        status: GameStatus.ongoing,
      );

      expect(shouldShowChessBoardTeachingsForGame(game), isFalse);
    });

    test('blocks local analysis positions', () {
      final game = _game(
        source: GameSource.localAnalysis,
        status: GameStatus.unknown,
      );

      expect(shouldShowChessBoardTeachingsForGame(game), isFalse);
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
