// Regression: appbar game-selector dropdown mini-board Row overflowed by
// ~4px because BoxDecoration border width (2px × 2 sides) was omitted from
// horizontal sizing while being counted in strip height.
//
// gameSelectorBoardFrameLayout is the strip-height / sizing helper; the live
// card re-resolves board side from LayoutBuilder so the board is always 1:1
// and flexes into remaining width after the eval bar.
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gameSelectorBoardFrameLayout', () {
    // Mirrors production defaults from _GameSelectorCard / ScreenUtil-ish values.
    const boardOuter = 179.6;
    const frameInset = 2.13;
    const borderWidth = 2.0;
    const evalBarWidth = 10.67;

    test('eval + board fit available width when eval bar is shown', () {
      final layout = gameSelectorBoardFrameLayout(
        boardOuter: boardOuter,
        frameInset: frameInset,
        borderWidth: borderWidth,
        evalBarWidth: evalBarWidth,
        showEvalBar: true,
      );

      final contentBudget =
          boardOuter - frameInset * 2 - borderWidth * 2;

      expect(layout.innerWidth, closeTo(contentBudget, 1e-9));
      expect(layout.evalWidth, evalBarWidth);
      expect(
        layout.evalWidth + layout.boardSize,
        lessThanOrEqualTo(layout.innerWidth + 1e-9),
      );
      // The bug: without subtracting border, children summed to content+4.
      expect(
        layout.evalWidth + layout.boardSize,
        lessThanOrEqualTo(contentBudget + 1e-9),
      );
      expect(
        layout.evalWidth + layout.boardSize,
        closeTo(layout.innerWidth, 1e-9),
      );
    });

    test('board is square: side equals remaining width after eval', () {
      final withEval = gameSelectorBoardFrameLayout(
        boardOuter: boardOuter,
        frameInset: frameInset,
        borderWidth: borderWidth,
        evalBarWidth: evalBarWidth,
        showEvalBar: true,
      );
      // 1:1 board uses leftover width as its side length.
      expect(
        withEval.boardSize,
        closeTo(withEval.innerWidth - withEval.evalWidth, 1e-9),
      );
      // Frame height follows that same side (square + chrome).
      expect(
        withEval.frameHeight,
        closeTo(
          withEval.boardSize + frameInset * 2 + borderWidth * 2,
          1e-9,
        ),
      );

      final noEval = gameSelectorBoardFrameLayout(
        boardOuter: boardOuter,
        frameInset: frameInset,
        borderWidth: borderWidth,
        evalBarWidth: evalBarWidth,
        showEvalBar: false,
      );
      // No gauge → full content width is the square side.
      expect(noEval.boardSize, closeTo(noEval.innerWidth, 1e-9));
    });

    test('board alone fits available width when eval bar is hidden', () {
      final layout = gameSelectorBoardFrameLayout(
        boardOuter: boardOuter,
        frameInset: frameInset,
        borderWidth: borderWidth,
        evalBarWidth: evalBarWidth,
        showEvalBar: false,
      );

      final contentBudget =
          boardOuter - frameInset * 2 - borderWidth * 2;

      expect(layout.evalWidth, 0.0);
      expect(layout.boardSize, closeTo(contentBudget, 1e-9));
      expect(layout.boardSize, lessThanOrEqualTo(layout.innerWidth + 1e-9));
      // Outer frame height matches card width (square no-eval board + chrome).
      expect(layout.frameHeight, closeTo(boardOuter, 1e-9));
    });

    test('border accounts for the historical 4px overflow', () {
      // Same numbers that produced RenderFlex overflowed by 4.0 pixels.
      final buggyInner = boardOuter - frameInset * 2; // forgot border
      final fixed = gameSelectorBoardFrameLayout(
        boardOuter: boardOuter,
        frameInset: frameInset,
        borderWidth: borderWidth,
        evalBarWidth: evalBarWidth,
        showEvalBar: true,
      );

      final overflowIfUnfixed = buggyInner - fixed.innerWidth;
      expect(overflowIfUnfixed, closeTo(borderWidth * 2, 1e-9));
      expect(overflowIfUnfixed, closeTo(4.0, 1e-9));
    });

    test('uses logical card width 168 with 2.w-like inset', () {
      // Representative unscaled / lightly scaled phone values.
      final layout = gameSelectorBoardFrameLayout(
        boardOuter: 168.0,
        frameInset: 2.0,
        borderWidth: 2.0,
        evalBarWidth: 10.0,
        showEvalBar: true,
      );

      // content = 168 - 4 - 4 = 160; board = 160 - 10 = 150 (1:1 side)
      expect(layout.innerWidth, 160.0);
      expect(layout.evalWidth, 10.0);
      expect(layout.boardSize, 150.0);
      expect(layout.evalWidth + layout.boardSize, 160.0);
    });

    test('eval bar cannot consume the whole content width', () {
      final layout = gameSelectorBoardFrameLayout(
        boardOuter: 40.0,
        frameInset: 2.0,
        borderWidth: 2.0,
        evalBarWidth: 100.0, // wider than content
        showEvalBar: true,
      );
      // Leave ≥1px for the board so it still paints a square.
      expect(layout.boardSize, greaterThanOrEqualTo(1.0));
      expect(layout.evalWidth + layout.boardSize, layout.innerWidth);
    });
  });
}
