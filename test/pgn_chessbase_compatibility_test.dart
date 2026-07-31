import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/notation/pgn_move_number_repair.dart';
import 'package:chessever2/utils/pgn_export_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Users pasted our PGN into ChessBase and lost every clock, while Lichess and
/// chess.com showed them fine. Those two read `[%clk]` directly; ChessBase does
/// not store time remaining at all — it converts each `[%clk]` into elapsed
/// time using the `TimeControl` tag, and drops the lot when that tag makes no
/// sense. We were shipping `[TimeControl "standard"]`, a speed category.
///
/// Two smaller defects rode along in the same movetext: the machine tags were
/// split across two `{}` blocks per move (no other producer does that, and a
/// reader keeping one comment per move loses whichever it discards), and black
/// moves after a comment lost their `N...` indicator.
void main() {
  const senior = '''
[Event "Senior DM50+"]
[Site "https://chessever.com/games/ghAKkSCe"]
[Date "2026.07.31"]
[White "Rewitz, Poul"]
[Black "Nielsen, Frode Benedikt"]
[Result "1-0"]
[TimeControl "standard"]

1. b3 { [%clk 1:30:53] } d6 { [%clk 1:29:21] } 2. Bb2 { [%clk 1:31:04] } c6 { [%clk 1:29:34] } 1-0
''';

  test('an exported game never carries a category as TimeControl', () {
    final exported = exportGameToPgn(ChessGame.fromPgn('senior', senior));

    expect(exported, isNot(contains('[TimeControl "standard"]')));
    // Nothing legal can be built from "standard", so the tag is dropped rather
    // than guessed at — a wrong time control makes readers compute wrong times.
    expect(exported, isNot(contains('TimeControl')));
    // The clocks themselves are untouched.
    expect(exported, contains('[%clk 1:30:53]'));
  });

  test('a real tournament time control survives export as a PGN field', () {
    final game = ChessGame.fromPgn('tc', senior);
    final withField = game.copyWith(
      metadata: {...game.metadata, 'TimeControl': '40/5400+30:1800+30'},
    );

    expect(
      exportGameToPgn(withField),
      contains('[TimeControl "40/5400+30:1800+30"]'),
    );
  });

  test('canonical headers rewrite loose text and drop the unusable', () {
    expect(
      canonicalPgnHeaders({'TimeControl': '90 min + 30 sec / move'}),
      containsPair('TimeControl', '5400+30'),
    );
    expect(
      canonicalPgnHeaders({'TimeControl': 'standard'}),
      isNot(contains('TimeControl')),
    );
  });

  test('machine tags share one comment, eval first, like every producer', () {
    final game = ChessGame.fromPgn(
      'tags',
      '1. b3 { [%eval 0.0] [%clk 1:30:53] } d6 { [%eval 0.15] [%clk 1:29:21] } *',
    );
    final exported = exportGameToPgn(game);

    expect(exported, contains('{ [%eval 0.0] [%clk 1:30:53] }'));
    expect(exported, contains('{ [%eval 0.15] [%clk 1:29:21] }'));
    // The old shape: two blocks per move, clock first.
    expect(exported, isNot(contains('} { [%eval')));
  });

  test('a clock-only game still exports one comment per move', () {
    final exported = exportGameToPgn(ChessGame.fromPgn('senior', senior));
    expect(exported, contains('{ [%clk 1:30:53] }'));
    expect(exported, isNot(contains('} {')));
  });

  test('black moves after a comment keep their move number', () {
    final exported = exportGameToPgn(ChessGame.fromPgn('senior', senior));

    expect(exported, contains('1. b3 { [%clk 1:30:53] } 1... d6'));
    expect(exported, contains('2. Bb2 { [%clk 1:31:04] } 2... c6'));
    // The exported movetext must re-parse to the same game.
    final reparsed = ChessGame.fromPgn('again', exported);
    expect(reparsed.mainline.map((m) => m.san).toList(), [
      'b3',
      'd6',
      'Bb2',
      'c6',
    ]);
    expect(reparsed.mainline[1].clockTime, '1:29:21');
  });

  group('restoreBlackMoveNumbers', () {
    test('leaves an already-correct movetext alone', () {
      const movetext = '1. e4 e5 2. Nf3 Nc6 1-0';
      expect(restoreBlackMoveNumbers(movetext), movetext);
    });

    test('never inserts before a white move', () {
      expect(
        restoreBlackMoveNumbers('1. e4 { c } e5 { c } 2. Nf3 *'),
        '1. e4 { c } 1... e5 { c } 2. Nf3 *',
      );
    });

    test('counts plies through variations without leaking their numbering', () {
      expect(
        restoreBlackMoveNumbers('1. e4 { c } e5 ( 1... c5 2. Nf3 ) 2. d4 { c } d5 *'),
        '1. e4 { c } 1... e5 ( 1... c5 2. Nf3 ) 2. d4 { c } 2... d5 *',
      );
    });

    test('ignores move-number-like text inside comments', () {
      // A comment is opaque: `2... Qd8` in prose must not move the counter.
      expect(
        restoreBlackMoveNumbers('1. e4 { better was 2... Qd8 } e5 *'),
        '1. e4 { better was 2... Qd8 } 1... e5 *',
      );
    });

    test('handles a NAG between the move and the comment', () {
      expect(
        restoreBlackMoveNumbers(r'1. e4 $1 $240 { c } e5 *'),
        r'1. e4 $1 $240 { c } 1... e5 *',
      );
    });

    test('a game starting from a black-to-move FEN is untouched', () {
      const movetext = '1... e5 2. Nf3 { c } 2... Nc6 *';
      expect(restoreBlackMoveNumbers(movetext), movetext);
    });
  });
}
