import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new_worker.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
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

  group('Gamebase clock handoff', () {
    test('preserves structured move clocks for the board parser', () {
      final pgn = buildPgnFromGamebaseData({
        'md': {'White': 'White', 'Black': 'Black', 'Result': '*'},
        'm': [
          {'u': 'e2e4', 'ct': '1:30:55'},
          {'u': 'e7e5', 'ct': '1:30:17'},
          {'u': 'g1f3', 'ct': '1:29:42'},
          {'u': 'b8c6', 'ct': '1:29:07'},
        ],
      });

      expect(pgn, isNotNull);
      final parsed = parsePgnWorker(pgn!);

      expect(parsed.moveTimes, ['1:30:55', '1:30:17', '1:29:42', '1:29:07']);
    });

    test(
      'Library route prefers structured clocks over a clockless raw PGN',
      () {
        const rawPgn =
            '[White "White"]\n[Black "Black"]\n[Result "*"]\n\n'
            '1. e4 e5 2. Nf3 Nc6 *';
        final data = <String, dynamic>{
          'md': {'White': 'White', 'Black': 'Black', 'Result': '*'},
          'm': [
            {'u': 'e2e4', 'ct': '1:30:55'},
            {'u': 'e7e5', 'ct': '1:30:17'},
            {'u': 'g1f3', 'ct': '1:29:42'},
            {'u': 'b8c6', 'ct': '1:29:07'},
          ],
        };

        final selected = selectGamebaseBoardPgn(rawPgn: rawPgn, data: data);
        final parsed = parsePgnWorker(selected!);

        expect(selected, contains('[%clk 1:30:55]'));
        expect(parsed.moveTimes, ['1:30:55', '1:30:17', '1:29:42', '1:29:07']);
      },
    );
  });

  group('GamesTourModel.fromGame', () {
    test('uses a completed PGN position over a stale initial FEN', () {
      const completedPgn = '''
[Event "3+0 Thursday"]

1. e4 e5 2. Nf3 Nc6 1-0
''';
      const initialFen =
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      const completedFen =
          'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';

      final game = Games(
        id: 'game-completed',
        roundId: 'round-3',
        roundSlug: 'round-3',
        tourId: 'tour-1',
        tourSlug: 'tour-1',
        lastMove: 'b8c6',
        status: '1-0',
        fen: initialFen,
        pgn: completedPgn,
        players: [
          Player(
            name: 'White Player',
            title: 'GM',
            rating: 2700,
            fideId: 1,
            fed: 'NOR',
            clock: 0,
            team: '',
          ),
          Player(
            name: 'Black Player',
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

      expect(model.fen, completedFen);
    });

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
