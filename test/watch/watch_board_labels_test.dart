import 'package:chessever2/watch/core/watch_models.dart';
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:chessever2/watch/ui/watch_visuals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  group('watchLastMoveLabel', () {
    test('names the moved piece from the position after the move', () {
      expect(
        watchLastMoveLabel('7k/5N1p/8/8/8/8/8/6K1 b - - 0 1', 'e5f7'),
        'Ne5–f7',
      );
    });
    test('pawn moves carry no letter', () {
      expect(
        watchLastMoveLabel(
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
          'e2e4',
        ),
        'e2–e4',
      );
    });
    test('castling and promotion', () {
      expect(watchLastMoveLabel('8/8/8/8/8/8/8/5RK1 b - - 0 1', 'e1g1'), 'O-O');
      expect(
        watchLastMoveLabel('8/8/8/8/8/8/8/2KR4 b - - 0 1', 'e1c1'),
        'O-O-O',
      );
      expect(
        watchLastMoveLabel('4Q3/8/8/8/8/8/8/8 b - - 0 1', 'e7e8q'),
        'e7–e8=Q',
      );
    });
    test('non-UCI and missing input pass through', () {
      expect(watchLastMoveLabel(start, null), isNull);
      expect(watchLastMoveLabel(start, 'Nf3'), 'Nf3');
      expect(watchLastMoveLabel(null, 'g1f3'), 'g1–f3');
    });
  });

  test('watchPositionDescription groups by side, king first', () {
    final squares = watchFenSquares('7k/5N1p/8/8/8/6P1/5PKP/2q5 b - - 0 1')!;
    expect(
      watchPositionDescription(squares),
      'White: king g2, knight f7, pawns f2, g3, h2. '
      'Black: king h8, queen c1, pawn h7.',
    );
  });

  group('watchNextRound', () {
    final now = DateTime(2026, 11, 12, 11);
    test('today, tomorrow and later in the week', () {
      expect(
        watchNextRound(DateTime(2026, 11, 12, 14), now),
        'Next round 14:00',
      );
      expect(
        watchNextRound(DateTime(2026, 11, 13, 16, 15), now),
        'Next round Tomorrow 16:15',
      );
      expect(
        watchNextRound(DateTime(2026, 11, 15, 9), now),
        'Next round Sun 09:00',
      );
    });
    test('a round that already started gives no label', () {
      expect(watchNextRound(DateTime(2026, 11, 12, 10), now), isNull);
      expect(watchNextRound(null, now), isNull);
    });
  });

  test('power constraint slows live polling to every fourth tick', () {
    final normal = [
      for (var t = 1; t <= 8; t++) watchShouldPoll(t, constrained: false),
    ];
    final low = [
      for (var t = 1; t <= 8; t++) watchShouldPoll(t, constrained: true),
    ];
    expect(normal.every((p) => p), isTrue);
    expect(low, [false, false, false, true, false, false, false, true]);
  });
}
