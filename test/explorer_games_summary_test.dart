import 'package:chessever2/screens/gamebase/models/move_aggregate.dart';
import 'package:chessever2/screens/gamebase/utils/continuation_line.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

// Trello #984 "Explorer improvements": pure-logic coverage for the '∑' summary
// row aggregation and the game-card continuation SAN replay helper.
void main() {
  group('MoveAggregatesSummary.fromAggregates', () {
    test('sums W/D/L and total across aggregates, weighted rates', () {
      final summary = MoveAggregatesSummary.fromAggregates([
        MoveAggregate(
          uci: 'e2e4',
          white: 3,
          black: 2,
          draws: 1,
          total: 6,
          lastPlayed: DateTime(2024, 1, 1),
        ),
        MoveAggregate(
          uci: 'd2d4',
          white: 1,
          black: 1,
          draws: 0,
          total: 2,
          lastPlayed: DateTime(2025, 6, 5),
        ),
      ]);

      expect(summary.white, 4);
      expect(summary.draws, 1);
      expect(summary.black, 3);
      expect(summary.total, 8);
      expect(summary.whiteRate, closeTo(0.5, 1e-9));
      expect(summary.drawRate, closeTo(0.125, 1e-9));
      expect(summary.blackRate, closeTo(0.375, 1e-9));
      expect(summary.lastPlayed, DateTime(2025, 6, 5));
      expect(summary.formattedTotal, '8');
    });

    test('empty aggregate list yields zero totals and rates', () {
      final summary = MoveAggregatesSummary.fromAggregates(const []);
      expect(summary.total, 0);
      expect(summary.whiteRate, 0.0);
      expect(summary.drawRate, 0.0);
      expect(summary.blackRate, 0.0);
      expect(summary.lastPlayed, isNull);
    });
  });

  group('formatGamebaseGameCount', () {
    test('formats plain, thousands and millions', () {
      expect(formatGamebaseGameCount(999), '999');
      expect(formatGamebaseGameCount(1500), '1.5K');
      expect(formatGamebaseGameCount(2400000), '2.4M');
    });
  });

  group('buildContinuationLine', () {
    test('replays UCIs from the anchor into SANs and per-ply FENs', () {
      final line = buildContinuationLine(kInitialFEN, [
        'e2e4',
        'e7e5',
        'g1f3',
      ]);

      expect(line.sans, ['e4', 'e5', 'Nf3']);
      expect(line.fens.length, 4);
      expect(line.fens.first, kInitialFEN);
      expect(
        line.fens[1].startsWith('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b'),
        isTrue,
      );
    });

    test('stops at the first illegal move, keeping the legal prefix', () {
      final line = buildContinuationLine(kInitialFEN, ['e2e4', 'e2e4']);
      expect(line.sans, ['e4']);
      expect(line.fens.length, 2);
    });

    test('handles standard castling UCI (e1g1 → O-O)', () {
      const fen =
          'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4';
      final line = buildContinuationLine(fen, ['e1g1']);
      expect(line.sans, ['O-O']);
    });

    test('invalid anchor FEN returns an empty line', () {
      final line = buildContinuationLine('not-a-fen', ['e2e4']);
      expect(line.isEmpty, isTrue);
      expect(line.fens, ['not-a-fen']);
    });
  });

  group('continuationChipLabel', () {
    test('white-to-move anchor: numbers white plies only', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 3';
      expect(continuationChipLabel(fen, 0, 'e4'), '3. e4');
      expect(continuationChipLabel(fen, 1, 'e5'), 'e5');
      expect(continuationChipLabel(fen, 2, 'Nf3'), '4. Nf3');
    });

    test('black-to-move anchor: leading black ply gets ellipsis prefix', () {
      const fen =
          'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 5';
      expect(continuationChipLabel(fen, 0, 'Nc6'), '5… Nc6');
      expect(continuationChipLabel(fen, 1, 'Nf3'), '6. Nf3');
      expect(continuationChipLabel(fen, 2, 'Bc5'), 'Bc5');
    });
  });
}
