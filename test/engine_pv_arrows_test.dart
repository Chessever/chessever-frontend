import 'package:chessever2/screens/chessboard/utils/engine_pv_arrows.dart';
import 'package:chessever2/screens/chessboard/utils/engine_pv_palette.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _afterE4Fen =
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

void main() {
  group('shouldDrawEnginePvArrows', () {
    test('follows Show Arrows and engine visibility on every surface', () {
      expect(
        shouldDrawEnginePvArrows(showEngineAnalysis: true, showPvArrows: true),
        isTrue,
      );
      expect(
        shouldDrawEnginePvArrows(showEngineAnalysis: true, showPvArrows: false),
        isFalse,
      );
      expect(
        shouldDrawEnginePvArrows(showEngineAnalysis: false, showPvArrows: true),
        isFalse,
      );
      expect(
        shouldDrawEnginePvArrows(
          showEngineAnalysis: true,
          showPvArrows: true,
          isPvPreviewActive: true,
        ),
        isFalse,
      );
    });
  });

  group('resolveEnginePvBoardArrows', () {
    const firstMoves = <String>['e2e4', 'd2d4', 'g1f3'];

    test('paints ranked arrows when Show Arrows is on', () {
      final shapes = resolveEnginePvBoardArrows(
        showEngineAnalysis: true,
        showPvArrows: true,
        isPvPreviewActive: false,
        rankedFirstMoveUcis: firstMoves,
        maxArrows: 3,
        boardFen: _startFen,
        evalFen: _startFen,
      );

      final arrows = shapes.whereType<Arrow>().toList();
      expect(arrows, hasLength(3));
      expect(arrows[0].orig, Square.fromName('e2'));
      expect(arrows[0].dest, Square.fromName('e4'));
      expect(arrows[1].orig, Square.fromName('d2'));
      expect(arrows[1].dest, Square.fromName('d4'));
      expect(arrows[2].orig, Square.fromName('g1'));
      expect(arrows[2].dest, Square.fromName('f3'));
      expect(
        arrows[0].color,
        engineArrowColorForRank(enginePvVariantBaseColor(0), 0),
      );
      expect(arrows[0].scale, greaterThan(arrows[1].scale));
    });

    test('stays empty when Show Arrows is off', () {
      expect(
        resolveEnginePvBoardArrows(
          showEngineAnalysis: true,
          showPvArrows: false,
          isPvPreviewActive: false,
          rankedFirstMoveUcis: firstMoves,
          maxArrows: 3,
          boardFen: _startFen,
          evalFen: _startFen,
        ),
        isEmpty,
      );
    });

    test('stays empty when engine analysis is off', () {
      expect(
        resolveEnginePvBoardArrows(
          showEngineAnalysis: false,
          showPvArrows: true,
          isPvPreviewActive: false,
          rankedFirstMoveUcis: firstMoves,
          maxArrows: 3,
          boardFen: _startFen,
          evalFen: _startFen,
        ),
        isEmpty,
      );
    });

    test('stays empty while a PV preview is walking off the eval root', () {
      expect(
        resolveEnginePvBoardArrows(
          showEngineAnalysis: true,
          showPvArrows: true,
          isPvPreviewActive: true,
          rankedFirstMoveUcis: firstMoves,
          maxArrows: 3,
          boardFen: _afterE4Fen,
          evalFen: _startFen,
        ),
        isEmpty,
      );
    });

    test('stays empty when eval FEN is a different position', () {
      expect(
        resolveEnginePvBoardArrows(
          showEngineAnalysis: true,
          showPvArrows: true,
          isPvPreviewActive: false,
          rankedFirstMoveUcis: firstMoves,
          maxArrows: 3,
          boardFen: _afterE4Fen,
          evalFen: _startFen,
        ),
        isEmpty,
      );
    });

    test('honors Arrow Count independently of how many PVs exist', () {
      final shapes = resolveEnginePvBoardArrows(
        showEngineAnalysis: true,
        showPvArrows: true,
        isPvPreviewActive: false,
        rankedFirstMoveUcis: firstMoves,
        maxArrows: 1,
        boardFen: _startFen,
        evalFen: _startFen,
      );

      expect(shapes.whereType<Arrow>(), hasLength(1));
    });

    test('ignores halfmove/fullmove drift when matching eval to the board', () {
      const drifted =
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 5 12';
      expect(
        resolveEnginePvBoardArrows(
          showEngineAnalysis: true,
          showPvArrows: true,
          isPvPreviewActive: false,
          rankedFirstMoveUcis: firstMoves,
          maxArrows: 3,
          boardFen: _startFen,
          evalFen: drifted,
        ).whereType<Arrow>(),
        hasLength(3),
      );
    });
  });
}
