import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('event board placeholder filtering', () {
    test('hides unresolved starting-position placeholders', () {
      final placeholder = _game(
        id: 'future-placeholder',
        whiteName: '?',
        blackName: '?',
        fen: _initialFen,
      );

      expect(isEventBoardGameVisible(placeholder), isFalse);
    });

    test(
      'hides named unstarted pairings so future rounds are not board cards',
      () {
        final futurePairing = _game(
          id: 'future-pairing',
          whiteName: 'Player A',
          blackName: 'Player B',
          fen: _initialFen,
        );

        expect(isEventBoardGameVisible(futurePairing), isFalse);
      },
    );

    test('keeps real games with resolved players and moves', () {
      final liveGame = _game(
        id: 'live-game',
        whiteName: 'Player A',
        blackName: 'Player B',
        lastMove: 'e2e4',
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
      );

      expect(isEventBoardGameVisible(liveGame), isTrue);
    });

    test('keeps PGN-only games even when last_move is missing', () {
      final pgnGame = _game(
        id: 'pgn-game',
        whiteName: 'Player A',
        blackName: 'Player B',
        pgn: '[Event "Demo"]\n\n1. e4 e5 2. Nf3',
      );

      expect(isEventBoardGameVisible(pgnGame), isTrue);
    });
  });
}

const _initialFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

GamesTourModel _game({
  required String id,
  required String whiteName,
  required String blackName,
  String? lastMove,
  String? fen,
  String? pgn,
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player(whiteName),
    blackPlayer: _player(blackName),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'round-8',
    tourId: 'tour-1',
    lastMove: lastMove,
    fen: fen,
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
