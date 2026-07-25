import 'dart:io';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/board_eval_restart_policy.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the board provider's FEN normalization used by the restart policy.
String _normalizeFen(String fen) => fen.split(' ').take(4).join(' ');

String _fenCacheKey(String fen, {int multiPV = 4}) {
  final base = _normalizeFen(fen);
  return '${base}_pv$multiPV';
}

void main() {
  const fenA =
      'r2qkb1r/pp1nnpp1/2p1p3/3pPb1p/3P1P2/1N2B3/PPP3PP/R2QKBNR w KQkq - 0 8';
  const fenB = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

  group('hasCompleteUsableBoardEval', () {
    test('true when settled complete multiPV matches board FEN', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 4,
          requiredPrincipalVariationCount: 4,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
        ),
        isTrue,
      );
    });

    test('false while still evaluating (stockfish deepening)', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 4,
          requiredPrincipalVariationCount: 4,
          currentBoardFen: fenA,
          isEvaluating: true,
          normalizeFen: _normalizeFen,
        ),
        isFalse,
      );
    });

    test('false for a provisional rebased one-line continuation', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 1,
          requiredPrincipalVariationCount: 4,
          currentBoardFen: fenA,
          isEvaluating: true,
          normalizeFen: _normalizeFen,
        ),
        isFalse,
        reason: 'the configured MultiPV refresh must still be allowed to start',
      );
    });

    test('false for a settled partial MultiPV result', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 1,
          requiredPrincipalVariationCount: 4,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
        ),
        isFalse,
      );
    });

    test('false when PVs belong to a different FEN', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 4,
          requiredPrincipalVariationCount: 4,
          currentBoardFen: fenB,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
        ),
        isFalse,
      );
    });

    test('false when no PVs', () {
      expect(
        hasCompleteUsableBoardEval(
          principalVariationsBaseFen: fenA,
          principalVariationCount: 0,
          requiredPrincipalVariationCount: 4,
          currentBoardFen: fenA,
          isEvaluating: false,
          normalizeFen: _normalizeFen,
        ),
        isFalse,
      );
    });
  });

  group('MultiPV completeness', () {
    test(
      'deep one-line cache does not suppress requested five-line search',
      () {
        final eval = CloudEval(
          fen: fenA,
          knodes: 100,
          depth: 40,
          pvs: [Pv(moves: 'e2e4 e7e5', cp: 20)],
          requestedMultiPv: 1,
        );

        expect(cloudEvalSkipsBoardStockfish(eval, requiredMultiPv: 5), isFalse);
      },
    );

    test('deep complete cache suppresses redundant local search', () {
      final eval = CloudEval(
        fen: fenA,
        knodes: 100,
        depth: 40,
        pvs: List.generate(
          5,
          (index) => Pv(moves: 'e2e4 e7e5', cp: 20 - index),
        ),
        requestedMultiPv: 5,
      );

      expect(cloudEvalSkipsBoardStockfish(eval, requiredMultiPv: 5), isTrue);
    });
  });

  group('decideBoardEvalStart — same-FEN thrash regression', () {
    final keyA = _fenCacheKey(fenA);
    final keyB = _fenCacheKey(fenB);

    test('repeated same-FEN force after complete cascade does not restart', () {
      // Simulates: CASCADE APPLY complete → visible-page force re-trigger × N
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
      // Settled on A with complete PVs; board moves to B.
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
        // PVs still for A or cleared → not complete for B
        hasCompleteUsableResultForKey: false,
        forceRestart: false,
      );
      expect(onNewFenB.shouldStart, isTrue);
      expect(onNewFenB.action, BoardEvalStartAction.start);
    });

    test(
      'forceRestart still re-evaluates complete same FEN (settings/threats)',
      () {
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
      },
    );

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

  group('provider wiring (shipped control path is used)', () {
    test('board provider imports and calls the restart policy', () {
      // Structural check: the shipped notifier file must wire the pure policy
      // into the real eval entry points (not a reimplementation in tests).
      final source =
          File(
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
      expect(
        RegExp(
          r'principalVariations: rebasedLines,[\s\S]{0,400}isEvaluating: true,',
        ).hasMatch(source),
        isTrue,
        reason:
            'the one-line committed-move continuation must remain provisional',
      );
      // Must not auto-force every visible-page schedule (that bypassed coalesce).
      expect(
        source.contains(
          'final shouldForce = force || (visibleIndex == index);',
        ),
        isFalse,
      );
      expect(
        source.contains('if (evaluationResolved && lastEvaluatedFen != null)'),
        isTrue,
        reason:
            'cancelled evaluations must not reset the retry circuit breaker',
      );
      expect(
        source.contains('allowInDebug: _allowBoardStockfishInDebug'),
        isTrue,
        reason:
            'the foreground board must be able to fill cache misses in debug',
      );
      expect(
        source.contains('const Duration(milliseconds: 250)'),
        isTrue,
        reason: 'unexpected cancellation retries must yield before retrying',
      );
    });
  });
}
