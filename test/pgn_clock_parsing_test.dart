import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/pgn_clock_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pgn clock utils', () {
    test('extracts clock strings from supported PGN clock formats', () {
      expect(extractPgnClockStringFromComment('{ [%clk 1:00:00] }'), '1:00:00');
      expect(extractPgnClockStringFromComment('{ [%clk 12:34] }'), '12:34');
      expect(
        extractPgnClockStringFromComment('{ [%clk 0:00:15.5] }'),
        '0:00:15',
      );
    });

    test('formats raw PGN clock strings for board display', () {
      expect(formatPgnClockForDisplay('0:03:00'), '03:00');
      expect(formatPgnClockForDisplay('12:34'), '12:34');
      expect(formatPgnClockForDisplay('1:00:05'), '1:00:05');
      expect(formatClockDisplayFromSeconds(179), '02:59');
    });

    test(
      'detects historical positions even when navigator path is truncated',
      () {
        expect(
          isShowingLiveBoardPosition(
            currentFen:
                'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
            liveFen:
                'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
            currentMoveIndex: 1,
            latestMainlineIndex: 3,
            isInAnalysisVariation: false,
          ),
          isFalse,
        );
      },
    );

    test('never treats analysis variations as live position', () {
      expect(
        isShowingLiveBoardPosition(
          currentFen:
              'r1bqkbnr/pppp1ppp/8/4p3/4P3/2n2N2/PPPP1PPP/RNBQKB1R w KQkq - 1 3',
          liveFen:
              'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
          currentMoveIndex: 4,
          latestMainlineIndex: 3,
          isInAnalysisVariation: true,
        ),
        isFalse,
      );
    });
  });

  group('ChessGame.fromPgn', () {
    test('captures MM:SS and fractional clock comments in the mainline', () {
      const pgn =
          '1. d4 { [%clk 0:03:00] } 1... c5 { [%clk 0:02:59.8] } 2. e4 { [%clk 12:34] }';

      final game = ChessGame.fromPgn('game-1', pgn);

      expect(game.mainline, hasLength(3));
      expect(game.mainline[0].clockTime, '0:03:00');
      expect(game.mainline[1].clockTime, '0:02:59');
      expect(game.mainline[2].clockTime, '12:34');
    });
  });

  group('GamesTourModel.fromGame', () {
    test('falls back to PGN clocks when live snapshots are absent', () {
      const pgn =
          '1. d4 { [%clk 0:03:00] } 1... c5 { [%clk 0:03:00] } '
          '2. e4 { [%clk 0:02:58] } 2... cxd4 { [%clk 0:02:59] } '
          '3. c3 { [%clk 0:02:58] }';

      final game = Games(
        id: 'game-1',
        roundId: 'round-1',
        roundSlug: 'round-1',
        tourId: 'tour-1',
        tourSlug: 'tour-1',
        lastMove: 'c2c3',
        status: '*',
        pgn: pgn,
        players: [
          Player(
            name: 'White, Player',
            title: 'GM',
            rating: 2700,
            fideId: 1,
            fed: 'NOR',
            clock: 0,
            team: '',
          ),
          Player(
            name: 'Black, Player',
            title: 'GM',
            rating: 2680,
            fideId: 2,
            fed: 'IND',
            clock: 0,
            team: '',
          ),
        ],
      );

      final model = GamesTourModel.fromGame(game);

      expect(model.whiteClockSeconds, 178);
      expect(model.blackClockSeconds, 179);
      expect(model.whiteTimeDisplay, '02:58');
      expect(model.blackTimeDisplay, '02:59');
    });
  });
}
