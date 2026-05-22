import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatGameCardLastMoveNotation', () {
    test('formats standard castling UCI as SAN', () {
      expect(
        formatGameCardLastMoveNotation(
          lastMove: 'e1g1',
          fen: '4k3/8/8/8/8/8/8/5RK1 b - - 1 5',
        ),
        '5.O-O',
      );
      expect(
        formatGameCardLastMoveNotation(
          lastMove: 'e1c1',
          fen: '4k3/8/8/8/8/8/8/2KR4 b - - 1 7',
        ),
        '7.O-O-O',
      );
      expect(
        formatGameCardLastMoveNotation(
          lastMove: 'e8g8',
          fen: '5rk1/8/8/8/8/8/8/4K3 w - - 1 12',
        ),
        '11...O-O',
      );
      expect(
        formatGameCardLastMoveNotation(
          lastMove: 'e8c8',
          fen: '2kr4/8/8/8/8/8/8/4K3 w - - 1 14',
        ),
        '13...O-O-O',
      );
    });

    test('formats dartchess king-to-rook castling UCI as SAN', () {
      expect(
        formatGameCardLastMoveNotation(
          lastMove: 'e1h1',
          fen: '4k3/8/8/8/8/8/8/5RK1 b - - 1 5',
        ),
        '5.O-O',
      );
      expect(
        formatGameCardLastMoveNotation(
          lastMove: 'e1a1',
          fen: '4k3/8/8/8/8/8/8/2KR4 b - - 1 7',
        ),
        '7.O-O-O',
      );
      expect(
        formatGameCardLastMoveNotation(
          lastMove: 'e8h8',
          fen: '5rk1/8/8/8/8/8/8/4K3 w - - 1 12',
        ),
        '11...O-O',
      );
      expect(
        formatGameCardLastMoveNotation(
          lastMove: 'e8a8',
          fen: '2kr4/8/8/8/8/8/8/4K3 w - - 1 14',
        ),
        '13...O-O-O',
      );
    });

    test('keeps castling check suffix from the post-move FEN', () {
      expect(
        formatGameCardLastMoveNotation(
          lastMove: 'e1c1',
          fen: '3k4/8/8/8/8/8/8/2KR4 b - - 1 10',
        ),
        '10.O-O-O+',
      );
    });

    test('falls back to castling SAN when FEN is unavailable', () {
      expect(
        formatGameCardLastMoveNotation(lastMove: 'e1g1', fen: null),
        'O-O',
      );
      expect(
        formatGameCardLastMoveNotation(lastMove: 'e8a8', fen: ''),
        'O-O-O',
      );
    });
  });
}
