import 'dart:io' as io;
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/board_eval_restart_policy.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the board provider's FEN normalization used by the restart policy.
String _normalizeFen(String fen) => fen.split(' ').take(4).join(' ');

String _fenCacheKey(String fen, {int multiPV = 4}) {
  final base = _normalizeFen(fen);
  return '${base}_pv$multiPV';
}

AnalysisLine _line(String uci, {double eval = 0.3}) {
  final moves = uci
      .split(' ')
      .where((t) => t.isNotEmpty)
      .map((t) => Move.parse(t)!)
      .toList(growable: false);
  return AnalysisLine(
    moves: moves,
    sanMoves: List.filled(moves.length, 'X'),
    evaluation: eval,
  );
}

void main() {
  const fenA =
      'r2qkb1r/pp1nnpp1/2p1p3/3pPb1p/3P1P2/1N2B3/PPP3PP/R2QKBNR w KQkq - 0 8';
  const fenB = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

  group('boardEvalTargetPvWidth', () {
    test('uses configured MultiPV when legal moves are plentiful', () {
      expect(
        boardEvalTargetPvWidth(configuredMultiPv: 3, maxLegalLines: 20),
        3,
      );
    });

    test('caps by legal-move count when position is constrained', () {
      expect(boardEvalTargetPvWidth(configuredMultiPv: 5, maxLegalLines: 2), 2);
    });

    test('zero legal moves yields zero target', () {
      expect(boardEvalTargetPvWidth(configuredMultiPv: 3, maxLegalLines: 0), 0);
    });
  });

  group('boardEvalNeedsMoreDepth / shallow settle', () {
    test('true when depth is below the interim floor', () {
      expect(boardEvalNeedsMoreDepth(reachedDepth: 4), isTrue);
      expect(
        boardEvalNeedsMoreDepth(reachedDepth: boardEvalMinCompleteDepth - 1),
        isTrue,
      );
    });

    test('false at or above the interim floor', () {
      expect(
        boardEvalNeedsMoreDepth(reachedDepth: boardEvalMinCompleteDepth),
        isFalse,
      );
      expect(boardEvalNeedsMoreDepth(reachedDepth: 30), isFalse);
    });

    test('mate never needs more depth', () {
      expect(boardEvalNeedsMoreDepth(reachedDepth: 2, isMate: true), isFalse);
    });

    test(
      'shallow settle only blocks complete when search was truncated/active',
      () {
        expect(
          boardEvalShallowSettleBlocksComplete(
            reachedDepth: 5,
            searchStillActiveOrTruncated: true,
          ),
          isTrue,
        );
        // Natural budget exhaust at depth 5: do NOT block complete / thrash.
        expect(
          boardEvalShallowSettleBlocksComplete(
            reachedDepth: 5,
            searchStillActiveOrTruncated: false,
          ),
          isFalse,
        );
      },
    );
  });

  group('hasCompleteUsableBoardEval', () {
    test('true when settled complete multiPV matches board FEN', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 4,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
          configuredMultiPv: 4,
        ),
        isTrue,
      );
    });

    test('false while still evaluating (stockfish deepening)', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 4,
          currentBoardFen: fenA,
          isEvaluating: true,
          normalizeFen: _normalizeFen,
          configuredMultiPv: 4,
        ),
        isFalse,
      );
    });

    test('false when PVs belong to a different FEN', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 4,
          currentBoardFen: fenB,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
          configuredMultiPv: 4,
        ),
        isFalse,
      );
    });

    test('false when no PVs', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 0,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
          configuredMultiPv: 3,
        ),
        isFalse,
      );
    });

    test('false when only 1 line settled but user configured MultiPV is 3', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 1,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
          configuredMultiPv: 3,
        ),
        isFalse,
      );
    });

    test('false for 2 of 3 lines', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 2,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
          configuredMultiPv: 3,
        ),
        isFalse,
      );
    });

    test('true when line count meets configured MultiPV', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 3,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
          configuredMultiPv: 3,
        ),
        isTrue,
      );
    });

    test(
      'full-width shallow settle is NOT complete when reachedDepth is interim',
      () {
        // Regression: depth display froze and lines stayed half-move because
        // width-only complete short-circuited while search was shallow.
        expect(
          hasCompleteUsableBoardEval(
            principalVariationsBaseFen: fenA,
            principalVariationCount: 3,
            currentBoardFen: fenA,
            isEvaluating: false,
            normalizeFen: _normalizeFen,
            configuredMultiPv: 3,
            reachedDepth: 4,
            minCompleteDepth: boardEvalMinCompleteDepth,
          ),
          isFalse,
        );
      },
    );

    test('full-width at sufficient depth is complete', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 3,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
          configuredMultiPv: 3,
          reachedDepth: boardEvalMinCompleteDepth,
        ),
        isTrue,
      );
    });

    test('true under-width when legal moves cannot produce more lines', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 2,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
          configuredMultiPv: 5,
          maxLegalLines: 2,
        ),
        isTrue,
      );
    });

    test('true under-width when width requirement is waived (mate)', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 1,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
          configuredMultiPv: 3,
          waiveWidthRequirement: true,
        ),
        isTrue,
      );
    });
  });

  group('boardEvalShouldRetryAfterSettle', () {
    test('retries incomplete MultiPV width', () {
      expect(
        boardEvalShouldRetryAfterSettle(
          principalVariationCount: 1,
          configuredMultiPv: 3,
        ),
        isTrue,
      );
    });

    test('does not retry full width after natural settle', () {
      expect(
        boardEvalShouldRetryAfterSettle(
          principalVariationCount: 3,
          configuredMultiPv: 3,
        ),
        isFalse,
      );
    });

    test('does not retry mate settles', () {
      expect(
        boardEvalShouldRetryAfterSettle(
          principalVariationCount: 1,
          configuredMultiPv: 3,
          isMate: true,
        ),
        isFalse,
      );
    });
  });

  group('decideBoardEvalStart — same-FEN thrash regression', () {
    final keyA = _fenCacheKey(fenA);
    final keyB = _fenCacheKey(fenB);

    test('repeated same-FEN force after complete cascade does not restart', () {
      var startCount = 0;
      for (var i = 0; i < 20; i++) {
        final decision = decideBoardEvalStart(
          requestedCacheKey: keyA,
          activeEvalKey: null,
          hasActiveRequest: false,
          activeRequestIsStale: false,
          hasCompleteUsableResultForKey: true,
          forceRestart: false,
        );
        if (decision.shouldStart) startCount++;
        expect(
          decision.action,
          BoardEvalStartAction.skipAlreadyComplete,
          reason: 'iteration $i must no-op after complete cascade',
        );
      }
      expect(startCount, 0);
    });

    test('incomplete-width settle is NOT skipAlreadyComplete — restarts', () {
      final decision = decideBoardEvalStart(
        requestedCacheKey: keyA,
        activeEvalKey: null,
        hasActiveRequest: false,
        activeRequestIsStale: false,
        hasCompleteUsableResultForKey: false,
        forceRestart: false,
      );
      expect(decision.shouldStart, isTrue);
      expect(decision.action, BoardEvalStartAction.start);
      expect(decision.reason, 'needs evaluation');
    });

    test('in-flight same-FEN force coalesces instead of restarting', () {
      var startCount = 0;
      for (var i = 0; i < 10; i++) {
        final decision = decideBoardEvalStart(
          requestedCacheKey: keyA,
          activeEvalKey: keyA,
          hasActiveRequest: true,
          activeRequestIsStale: false,
          hasCompleteUsableResultForKey: false,
          forceRestart: false,
        );
        if (decision.shouldStart) startCount++;
        expect(decision.action, BoardEvalStartAction.coalesceInFlight);
      }
      expect(startCount, 0);
    });

    test('real FEN change still evaluates', () {
      final afterCompleteOnA = decideBoardEvalStart(
        requestedCacheKey: keyA,
        activeEvalKey: null,
        hasActiveRequest: false,
        activeRequestIsStale: false,
        hasCompleteUsableResultForKey: true,
        forceRestart: false,
      );
      expect(afterCompleteOnA.shouldStart, isFalse);

      final onNewFenB = decideBoardEvalStart(
        requestedCacheKey: keyB,
        activeEvalKey: null,
        hasActiveRequest: false,
        activeRequestIsStale: false,
        hasCompleteUsableResultForKey: false,
        forceRestart: false,
      );
      expect(onNewFenB.shouldStart, isTrue);
      expect(onNewFenB.action, BoardEvalStartAction.start);
    });

    test('forceRestart still re-evaluates complete same FEN', () {
      final decision = decideBoardEvalStart(
        requestedCacheKey: keyA,
        activeEvalKey: keyA,
        hasActiveRequest: true,
        activeRequestIsStale: false,
        hasCompleteUsableResultForKey: true,
        forceRestart: true,
      );
      expect(decision.shouldStart, isTrue);
      expect(decision.reason, 'forceRestart');
    });

    test('stale in-flight request allows restart', () {
      final decision = decideBoardEvalStart(
        requestedCacheKey: keyA,
        activeEvalKey: keyA,
        hasActiveRequest: true,
        activeRequestIsStale: true,
        hasCompleteUsableResultForKey: false,
        forceRestart: false,
      );
      expect(decision.shouldStart, isTrue);
    });

    test('missing eval for current FEN still starts', () {
      final decision = decideBoardEvalStart(
        requestedCacheKey: keyA,
        activeEvalKey: null,
        hasActiveRequest: false,
        activeRequestIsStale: false,
        hasCompleteUsableResultForKey: false,
        forceRestart: false,
      );
      expect(decision.shouldStart, isTrue);
      expect(decision.reason, 'needs evaluation');
    });
  });

  group('mergeBoardPvProgress — multi-ply multi-line retention', () {
    test('keeps previous wider lines when incoming snapshot is narrower', () {
      final previous = [
        _line('e2e4 e7e5', eval: 0.3),
        _line('d2d4 d7d5', eval: 0.2),
        _line('c2c4 c7c5', eval: 0.1),
      ];
      final incoming = [_line('e2e4 e7e5 g1f3', eval: 0.35)];
      final merged = mergeBoardPvProgress(previous, incoming);
      expect(
        merged.length,
        3,
        reason: 'degraded frame must not collapse panel',
      );
      expect(merged[0].moves.length, 3, reason: 'line 0 takes longer incoming');
      expect(merged[0].evaluation, 0.35);
      expect(merged[1].evaluation, 0.2);
      expect(merged[2].evaluation, 0.1);
    });

    test('grows when incoming adds new multipv lines', () {
      final previous = [_line('e2e4', eval: 0.3)];
      final incoming = [
        _line('e2e4 e7e5', eval: 0.32),
        _line('d2d4', eval: 0.2),
        _line('c2c4', eval: 0.1),
      ];
      final merged = mergeBoardPvProgress(previous, incoming);
      expect(merged.length, 3);
      expect(merged[0].moves.length, 2);
      expect(merged[1].moves.first.uci, 'd2d4');
      expect(merged[2].moves.first.uci, 'c2c4');
    });

    test('empty incoming clears (callers only pass empty on real empty)', () {
      final previous = [_line('e2e4'), _line('d2d4')];
      expect(mergeBoardPvProgress(previous, const []), isEmpty);
    });

    test(
      'same-position multipv-1 progressive frame after 3 lines stays at 3',
      () {
        final previous = [
          _line('e2e4 e7e5', eval: 0.30),
          _line('d2d4 d7d5', eval: 0.20),
          _line('g1f3 b8c6', eval: 0.15),
        ];
        final degradedDepthFrame = [_line('e2e4 e7e5 g1f3', eval: 0.31)];
        final merged = mergeBoardPvProgress(previous, degradedDepthFrame);
        expect(merged.length, 3);
        expect(merged[1].moves.first.uci, 'd2d4');
        expect(merged[2].moves.first.uci, 'g1f3');
      },
    );

    test(
      'half-move incoming does not collapse multi-ply line with same first move',
      () {
        // Regression: engine depth advances, multipv 1 lands as a single
        // half-move before the rest of the PV is filled — panel showed only
        // "Nf3" etc. instead of the multi-ply body already known.
        final previous = [
          _line('e2e4 e7e5 g1f3 b8c6', eval: 0.30),
          _line('d2d4 d7d5', eval: 0.20),
        ];
        final halfMoveOnly = [
          _line('e2e4', eval: 0.31),
          _line('d2d4', eval: 0.21),
        ];
        final merged = mergeBoardPvProgress(previous, halfMoveOnly);
        expect(merged.length, 2);
        expect(
          merged[0].moves.length,
          4,
          reason: 'must retain multi-ply body, not flash one half-move',
        );
        expect(merged[0].evaluation, 0.31);
        expect(merged[1].moves.length, 2);
        expect(merged[1].evaluation, 0.21);
      },
    );

    test('prefix retention keeps longer PV when new is shorter prefix', () {
      final previous = [_line('e2e4 e7e5 g1f3', eval: 0.2)];
      final incoming = [_line('e2e4 e7e5', eval: 0.25)];
      final merged = mergeBoardPvProgress(previous, incoming);
      expect(merged.single.moves.length, 3);
      expect(merged.single.evaluation, 0.25);
    });
  });

  group('engine PV side ownership (white / black / threats)', () {
    // Starting position: white to move.
    const whiteToMoveFen =
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    // After 1.e4: black to move.
    const blackToMoveFen =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

    test('boardEvalAnalysisFen never flips side when threats is off', () {
      expect(
        boardEvalAnalysisFen(whiteToMoveFen, isThreatsMode: false),
        whiteToMoveFen,
      );
      expect(
        boardEvalAnalysisFen(blackToMoveFen, isThreatsMode: false),
        blackToMoveFen,
      );
      expect(boardEvalSideToMove(whiteToMoveFen), 'w');
      expect(boardEvalSideToMove(blackToMoveFen), 'b');
    });

    test('threats mode flips only the analysis FEN side to move', () {
      final threatOnWhite = boardEvalAnalysisFen(
        whiteToMoveFen,
        isThreatsMode: true,
      );
      final threatOnBlack = boardEvalAnalysisFen(
        blackToMoveFen,
        isThreatsMode: true,
      );
      expect(boardEvalSideToMove(threatOnWhite), 'b');
      expect(boardEvalSideToMove(threatOnBlack), 'w');
      // Piece placement unchanged.
      expect(threatOnWhite.split(' ').first, whiteToMoveFen.split(' ').first);
      expect(threatOnBlack.split(' ').first, blackToMoveFen.split(' ').first);
    });

    test(
      'white-to-move UCI PVs convert to SAN and first move is legal for white',
      () {
        // Real engine-style multipv for the start position.
        final lines = buildBoardAnalysisLinesFromUci(
          fen: whiteToMoveFen,
          pvMoveStrings: const ['e2e4 e7e5 g1f3', 'd2d4 d7d5', 'g1f3 b8c6'],
        );
        expect(lines.length, 3);
        expect(lines[0].sanMoves.first, 'e4');
        expect(lines[0].moves.first.uci, 'e2e4');
        expect(isFirstUciLegalForFen(whiteToMoveFen, 'e2e4'), isTrue);
        // Opposite-side black reply is NOT legal for white-to-move.
        expect(isFirstUciLegalForFen(whiteToMoveFen, 'e7e5'), isFalse);
        for (final line in lines) {
          expect(
            isFirstUciLegalForFen(whiteToMoveFen, line.moves.first.uci),
            isTrue,
            reason: 'PV ${line.moves.first.uci} must be legal for white',
          );
        }
      },
    );

    test(
      'black-to-move UCI PVs convert to SAN and first move is legal for black',
      () {
        final lines = buildBoardAnalysisLinesFromUci(
          fen: blackToMoveFen,
          pvMoveStrings: const ['e7e5 g1f3 b8c6', 'c7c5 g1f3', 'e7e6 d2d4'],
        );
        expect(lines.length, 3);
        expect(lines[0].sanMoves.first, 'e5');
        expect(lines[0].moves.first.uci, 'e7e5');
        expect(isFirstUciLegalForFen(blackToMoveFen, 'e7e5'), isTrue);
        // White's e2e4 is not legal when black is to move.
        expect(isFirstUciLegalForFen(blackToMoveFen, 'e2e4'), isFalse);
        for (final line in lines) {
          expect(
            isFirstUciLegalForFen(blackToMoveFen, line.moves.first.uci),
            isTrue,
            reason: 'PV ${line.moves.first.uci} must be legal for black',
          );
        }
      },
    );

    test(
      'stale opposite-side PVs fail board match and merge drops previous',
      () {
        // After a half-move the stored base is white-to-move but board is black.
        expect(
          boardPvLinesBelongToBoard(
            principalVariationsBaseFen: whiteToMoveFen,
            currentBoardFen: blackToMoveFen,
          ),
          isFalse,
        );
        expect(
          boardPvLinesBelongToBoard(
            principalVariationsBaseFen: blackToMoveFen,
            currentBoardFen: blackToMoveFen,
          ),
          isTrue,
        );

        // Previous white multipv must not re-attach when black-to-move arrives.
        final previousWhite = [
          _line('e2e4 e7e5', eval: 0.3),
          _line('d2d4 d7d5', eval: 0.2),
          _line('g1f3 b8c6', eval: 0.1),
        ];
        final incomingBlack = [_line('e7e5 g1f3', eval: 0.25)];
        final merged = mergeBoardPvProgressForPosition(
          previous: previousWhite,
          incoming: incomingBlack,
          previousBaseFen: whiteToMoveFen,
          currentBoardFen: blackToMoveFen,
        );
        expect(merged.length, 1, reason: 'must not keep white multipv tail');
        expect(merged.single.moves.first.uci, 'e7e5');
        expect(
          isFirstUciLegalForFen(blackToMoveFen, merged.single.moves.first.uci),
          isTrue,
        );
      },
    );

    test(
      'same-position merge still retains multi-line width (no regression)',
      () {
        final previous = [
          _line('e7e5 g1f3', eval: 0.2),
          _line('c7c5', eval: 0.1),
        ];
        final incoming = [_line('e7e5 g1f3 b8c6', eval: 0.22)];
        final merged = mergeBoardPvProgressForPosition(
          previous: previous,
          incoming: incoming,
          previousBaseFen: blackToMoveFen,
          currentBoardFen: blackToMoveFen,
        );
        expect(merged.length, 2);
        expect(merged[0].moves.length, 3);
        expect(merged[1].moves.first.uci, 'c7c5');
      },
    );

    test('formatEnginePvNotation: white-to-move numbering', () {
      final tokens = formatEnginePvNotation(const ['e4', 'e5', 'Nf3'], 1, true);
      expect(tokens, ['1.', 'e4', 'e5', '2.', 'Nf3']);
    });

    test('formatEnginePvNotation: black-to-move opens with N…', () {
      final tokens = formatEnginePvNotation(
        const ['e5', 'Nf3', 'Nc6'],
        1,
        false,
      );
      expect(tokens.first, '1\u2026');
      expect(tokens, ['1\u2026', 'e5', '2.', 'Nf3', 'Nc6']);
    });

    test(
      'formatEnginePvNotation: threats mode flips ownership on white-to-move board',
      () {
        // Board is white to move; threats analyses black — first move is black's.
        final tokens = formatEnginePvNotation(
          const ['e5', 'Nf3'],
          4,
          true,
          isThreatsMode: true,
        );
        expect(tokens.first, '4\u2026');
        expect(tokens, ['4\u2026', 'e5', '5.', 'Nf3']);
      },
    );

    test(
      'formatEnginePvNotation: threats mode on black-to-move board is white first',
      () {
        final tokens = formatEnginePvNotation(
          const ['e4', 'e5'],
          1,
          false,
          isThreatsMode: true,
        );
        expect(tokens, ['1.', 'e4', 'e5']);
      },
    );
  });

  group('provider wiring (shipped control path is used)', () {
    test('board provider imports and calls the restart policy', () {
      final source =
          io.File(
            'lib/screens/chessboard/provider/chess_board_screen_provider_new.dart',
          ).readAsStringSync();
      expect(
        source.contains(
          "import 'package:chessever2/screens/chessboard/provider/board_eval_restart_policy.dart';",
        ),
        isTrue,
      );
      expect(source.contains('decideBoardEvalStart('), isTrue);
      expect(source.contains('hasCompleteUsableBoardEval('), isTrue);
      expect(source.contains('configuredMultiPv:'), isTrue);
      expect(source.contains('mergeBoardPvProgress'), isTrue);
      expect(source.contains('mergeBoardPvProgressForPosition'), isTrue);
      expect(source.contains('boardEvalAnalysisFen'), isTrue);
      expect(source.contains('_evalApplyStillValid'), isTrue);
      expect(source.contains('boardPvLinesBelongToBoard'), isTrue);
      expect(source.contains('boardEvalShouldRetryAfterSettle'), isTrue);
      expect(source.contains('incomplete-board-settle'), isTrue);
      // Hard 10s search cap that froze depth must be gone.
      expect(source.contains('fallbackCap'), isFalse);
      expect(source.contains("const Duration(seconds: 10)"), isFalse);
      // 800ms first-eval shortcut that left half-move PVs must be gone.
      expect(source.contains("const Duration(milliseconds: 800)"), isFalse);
      // Progressive path must keep isEvaluating true for the live search.
      expect(
        source.contains('// Stay evaluating for the whole live search'),
        isTrue,
      );
      expect(
        source.contains(
          'final shouldForce = force || (visibleIndex == index);',
        ),
        isFalse,
      );
    });

    test('PV UI formats via shared formatEnginePvNotation helper', () {
      final source =
          io.File(
            'lib/screens/chessboard/chess_board_screen_new.dart',
          ).readAsStringSync();
      expect(
        source.contains(
          "import 'package:chessever2/screens/chessboard/provider/board_eval_restart_policy.dart';",
        ),
        isTrue,
      );
      expect(source.contains('formatEnginePvNotation('), isTrue);
    });

    test(
      'stockfish always re-asserts MultiPV; no mid-search self-heal stop',
      () {
        final source =
            io.File(
              'lib/screens/chessboard/provider/stockfish_singleton.dart',
            ).readAsStringSync();
        expect(
          source.contains("setoption name MultiPV value \$multiPV"),
          isTrue,
        );
        // Mid-search stop for MultiPV self-heal must not exist (froze depth).
        expect(source.contains('MultiPV self-heal'), isFalse);
        expect(
          source.contains("setoption name UCI_Chess960 value true"),
          isTrue,
        );
        // Board handoff still yields only with full MultiPV width.
        expect(source.contains('boardHandoffDepth'), isTrue);
        expect(source.contains('settled.length >= multiPV'), isTrue);
      },
    );

    test('cloud skip still requires requested MultiPV width', () {
      final source =
          io.File(
            'lib/screens/chessboard/provider/current_eval_provider.dart',
          ).readAsStringSync();
      expect(source.contains('usablePvCount < requestedMultiPv'), isTrue);
      expect(
        source.contains("pv.moves.trim().isNotEmpty"),
        isTrue,
        reason: 'empty cached PV rows must not count toward MultiPV width',
      );
    });

    test('board analysis must not pass allowInDebug: true', () {
      final source =
          io.File(
            'lib/screens/chessboard/provider/chess_board_screen_provider_new.dart',
          ).readAsStringSync();
      // Guardrail comment must remain; actual call sites must not opt in.
      expect(source.contains('DO NOT pass allowInDebug: true'), isTrue);
      // No evaluatePosition/warmUp call may pass allowInDebug: true.
      final callSites = RegExp(
        r'evaluatePosition\s*\([^)]*allowInDebug\s*:\s*true',
      );
      expect(callSites.hasMatch(source), isFalse);
      expect(source.contains('_allowBoardStockfishInDebug'), isFalse);
      expect(
        source.contains('kDebugMode && !kEnableStockfishInDebug'),
        isTrue,
        reason: 'the intentional debug cancellation must not be retried',
      );
    });

    test('cancelled and incomplete evaluations use a bounded retry path', () {
      final source =
          io.File(
            'lib/screens/chessboard/provider/chess_board_screen_provider_new.dart',
          ).readAsStringSync();
      expect(source.contains('_abandonPendingEvaluation'), isTrue);
      expect(
        source.contains('Future.delayed(const Duration(milliseconds: 250)'),
        isTrue,
      );
      // Always clear the pending/watchdog for the last FEN the request touched.
      // Gating resolve on evaluationResolved left cancelled/partial settles
      // pending forever and froze MultiPV (Arun #285 collateral — reverted).
      expect(source.contains('var evaluationResolved = false'), isFalse);
      expect(
        source.contains('if (evaluationResolved && lastEvaluatedFen != null)'),
        isFalse,
      );
      expect(
        source.contains('if (lastEvaluatedFen != null)'),
        isTrue,
        reason: 'finally must resolve pending eval for lastEvaluatedFen always',
      );
      expect(source.contains('_resolvePendingEvaluation(lastEvaluatedFen)'), isTrue);
    });

    test('nested PV preview rebases from the displayed prefix', () {
      final source =
          io.File(
            'lib/screens/chessboard/provider/chess_board_screen_provider_new.dart',
          ).readAsStringSync();
      expect(source.contains('final isNestedPreview ='), isTrue);
      expect(source.contains('currentPreviewMoveCount'), isTrue);
      expect(
        RegExp(
          r'lockedPositions\s*\.take\(currentPreviewMoveCount \+ 1\)',
        ).hasMatch(source),
        isTrue,
      );
      expect(source.contains('positionCursor.isLegal(move)'), isTrue);
      expect(source.contains('_pvPreviewEvaluationGeneration'), isTrue);
    });
  });

  group('cloud board-eval completeness', () {
    test('empty cached rows do not satisfy requested MultiPV width', () {
      final eval = CloudEval(
        fen: fenA,
        knodes: 100,
        depth: boardEvalSufficientDepth,
        pvs: [
          Pv(moves: 'e2e4', cp: 20),
          Pv(moves: '', cp: 10),
          Pv(moves: '   ', cp: 5),
        ],
      );

      expect(cloudEvalSkipsBoardStockfish(eval, requestedMultiPv: 3), isFalse);
    });

    test('full usable cached MultiPV can satisfy board evaluation', () {
      final eval = CloudEval(
        fen: fenA,
        knodes: 100,
        depth: boardEvalSufficientDepth,
        pvs: [
          Pv(moves: 'e2e4', cp: 20),
          Pv(moves: 'd2d4', cp: 10),
          Pv(moves: 'g1f3', cp: 5),
        ],
      );

      expect(cloudEvalSkipsBoardStockfish(eval, requestedMultiPv: 3), isTrue);
    });
  });
}
