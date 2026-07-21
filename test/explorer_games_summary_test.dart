import 'dart:io' as io;

import 'package:chessever2/screens/gamebase/models/move_aggregate.dart';
import 'package:chessever2/screens/gamebase/utils/continuation_line.dart';
import 'package:chessever2/screens/gamebase/widgets/move_statistics_panel.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

// Trello #984 "Explorer improvements": pure-logic coverage for the '∑' summary
// row aggregation and the game-card continuation SAN replay helper.
void main() {
  group('explorerMoveNumberLabelFromFen', () {
    test('white to move uses N. form from fullmove field', () {
      // Initial position: fullmove 1, white to move → "1."
      expect(explorerMoveNumberLabelFromFen(kInitialFEN), '1.');
      // After 1.e4 e5 2.Nf3, white to move on fullmove 2 → still mid-game fen:
      const afterNf3White =
          'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';
      expect(explorerMoveNumberLabelFromFen(afterNf3White), '3.');
    });

    test('black to move uses N... form from fullmove field', () {
      const afterE4 =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
      expect(explorerMoveNumberLabelFromFen(afterE4), '1...');
      const afterNf3 =
          'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
      expect(explorerMoveNumberLabelFromFen(afterNf3), '2...');
    });
  });

  group('SUM row matches move-row Games chip + move number (structural)', () {
    test('summary row wires fen/moves/filters, move label, chip, no UCI', () {
      final source =
          io.File(
            'lib/screens/gamebase/widgets/move_statistics_panel.dart',
          ).readAsStringSync();

      // Construction site threads explorer position context into SUM.
      expect(
        source,
        contains(
          '_MoveStatisticsSummaryRow(\n'
          '          aggregates: aggregates,\n'
          '          currentFen: state.currentFen,\n'
          '          exploredMoves: state.exploredMoves,\n'
          '          filters: state.filters,',
        ),
      );

      // SUM Moves column uses the shared label helper (same as peer rows).
      expect(
        source.contains('explorerMoveNumberLabelFromFen(currentFen)'),
        isTrue,
      );
      // Both peer and SUM open paths present in file; SUM must not pass uci.
      final summaryClassStart = source.indexOf(
        'class _MoveStatisticsSummaryRow',
      );
      final nextClass = source.indexOf(
        'class _MoveStatisticsPlaceholderRow',
        summaryClassStart,
      );
      expect(summaryClassStart, greaterThan(0));
      expect(nextClass, greaterThan(summaryClassStart));
      final summaryBlock = source.substring(summaryClassStart, nextClass);

      expect(summaryBlock, contains("Text(\n                    '∑'"));
      expect(
        summaryBlock,
        contains('moveNumberLabel = explorerMoveNumberLabelFromFen(currentFen)'),
      );
      expect(summaryBlock, contains('Icons.list_alt_rounded'));
      expect(summaryBlock, contains('PositionGamesSheet('));
      expect(summaryBlock, contains('fen: currentFen,'));
      expect(summaryBlock, contains('moves: exploredMoves,'));
      expect(summaryBlock, contains('filters: filters,'));
      // Position-level games: no single-move UCI filter on SUM.
      expect(summaryBlock, isNot(contains('uci:')));
      expect(summaryBlock, contains("title: 'Games for \$moveNumberLabel∑'"));
      // Chip styling parity with peer rows.
      expect(summaryBlock, contains('kPrimaryColor.withValues(alpha: 0.14)'));
      expect(summaryBlock, contains('message: \'Games\''));
      expect(summaryBlock, contains('.scaleXY('));
    });
  });

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

  group('full-game continuation (past API 20-ply cap)', () {
    // 24 half-moves from start — longer than notationPlies: 20.
    const longPgn =
        '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 '
        '6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7 '
        '11. c4 c6 12. cxb5 axb5 1-0';

    test('fromPgn yields full remainder past ply 20', () {
      const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final full = buildFullContinuationLine(
        anchorFen: start,
        gameId: 'g-long',
        pgn: longPgn,
      );
      expect(full, isNotNull);
      // 24 SANs in the PGN mainline.
      expect(full!.sans.length, greaterThan(20));
      expect(full.sans.length, 24);
      expect(full.fens.length, full.sans.length + 1);
      expect(full.sans.first, 'e4');
      expect(full.sans.last, 'axb5');
    });

    test('from mid-game anchor keeps only the rest of the game', () {
      // After 1.e4 e5 2.Nf3 — black to move.
      const afterNf3 =
          'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
      final full = buildFullContinuationLine(
        anchorFen: afterNf3,
        gameId: 'g-mid',
        pgn: longPgn,
      );
      expect(full, isNotNull);
      // Entire game 24 plies minus 3 already played.
      expect(full!.sans.length, 21);
      expect(full.sans.first, 'Nc6');
      expect(full.sans.last, 'axb5');
    });

    test('structured gamebase data path also builds full line', () {
      const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final uciData = {
        'sf': start,
        'md': {'Result': '1-0'},
        'm': [
          for (final u in const [
            'e2e4',
            'e7e5',
            'g1f3',
            'b8c6',
            'f1b5',
            'a7a6',
            'b5a4',
            'g8f6',
            'e1g1',
            'f8e7',
            'f1e1',
            'b7b5',
            'a4b3',
            'd7d6',
            'c2c3',
            'e8g8',
            'h2h3',
            'c6b8',
            'd2d4',
            'b8d7',
            'c3c4',
            'c7c6',
          ])
            {'u': u},
        ],
      };
      final full = buildFullContinuationLine(
        anchorFen: start,
        gameId: 'g-data',
        data: uciData,
      );
      expect(full, isNotNull);
      expect(full!.sans.length, 22);
      expect(full.sans.length, greaterThan(20));
    });
  });
}
