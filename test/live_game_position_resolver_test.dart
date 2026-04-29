import 'package:chessever2/screens/tour_detail/games_tour/utils/live_game_position_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveFreshestGameFen', () {
    const afterE4 =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
    const afterE4E5 =
        'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
    const pgnAfterE4 = '''
[Event "Test"]

1. e4 *
''';
    const pgnAfterE4E5 = '''
[Event "Test"]

1. e4 e5 *
''';

    test('uses PGN when PGN and last_move prove FEN is one ply stale', () {
      final fen = resolveFreshestGameFen(
        fen: afterE4,
        pgn: pgnAfterE4E5,
        lastMove: 'e7e5',
      );

      expect(fen, afterE4E5);
    });

    test('keeps FEN when PGN is behind the advertised last move', () {
      final fen = resolveFreshestGameFen(
        fen: afterE4E5,
        pgn: pgnAfterE4,
        lastMove: 'e7e5',
      );

      expect(fen, afterE4E5);
    });

    test('uses PGN when local FEN is missing', () {
      final fen = resolveFreshestGameFen(
        fen: null,
        pgn: pgnAfterE4E5,
        lastMove: 'e7e5',
      );

      expect(fen, afterE4E5);
    });

    test(
      'uses PGN when ply count shows it is newer even without last_move',
      () {
        final fen = resolveFreshestGameFen(
          fen: afterE4,
          pgn: pgnAfterE4E5,
          lastMove: null,
        );

        expect(fen, afterE4E5);
      },
    );
  });
}
