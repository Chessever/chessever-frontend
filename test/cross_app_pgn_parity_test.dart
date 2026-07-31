import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Copy on mobile, paste on desktop: the two apps must render the same game the
/// same way, move for move.
///
/// [kCrossAppParityPgn] and the expectations below are duplicated verbatim in
/// `chessever_frontend_desktop/test/cross_app_pgn_parity_test.dart`. Both suites
/// assert the same fixture resolves to the same classification, clock, eval and
/// glyph on every ply, so a change to either app's reader shows up as a failing
/// test in that app rather than as a discrepancy a user has to notice.
///
/// If you change what we write, change the fixture in BOTH repos in the same
/// commit.
const kCrossAppParityPgn = '''
[Event "Senior DM50+"]
[Site "https://chessever.com/games/ghAKkSCe"]
[Date "2026.07.31"]
[Round "7.2"]
[White "Rewitz, Poul"]
[Black "Nielsen, Frode Benedikt"]
[Result "1-0"]
[TimeControl "40/5400+30:1800+30"]

1. b3 \$6 \$244 { [%eval -0.32] [%clk 1:30:53] } 1... d6 \$247 { [%eval 0.16] [%clk 1:29:21] } 2. Bb2 \$1 \$242 { [%eval 0.14] [%clk 1:31:04] } 2... c6 \$3 \$240 { [%eval 0.25] [%clk 1:29:34] } 3. f4 \$4 \$243 { [%eval -0.16] [%clk 1:28:36] } 3... Nf6 \$2 \$245 { [%eval -0.13] [%clk 1:29:10] } 4. e3 \$4 \$246 { A real comment. } { [%eval -0.25] [%clk 1:27:12] } 1-0
''';

/// Classification each ply must resolve to, on both apps.
const kCrossAppParityClassifications = <int, GameMoveClassification>{
  0: GameMoveClassification.inaccuracy,
  1: GameMoveClassification.bookMove,
  2: GameMoveClassification.bestMove,
  3: GameMoveClassification.brilliant,
  4: GameMoveClassification.missedWin,
  5: GameMoveClassification.mistake,
  6: GameMoveClassification.blunder,
};

const kCrossAppParityClocks = <String>[
  '1:30:53',
  '1:29:21',
  '1:31:04',
  '1:29:34',
  '1:28:36',
  '1:29:10',
  '1:27:12',
];

const kCrossAppParityEvals = <String>[
  '-0.32',
  '0.16',
  '0.14',
  '0.25',
  '-0.16',
  '-0.13',
  '-0.25',
];

void main() {
  final game = ChessGame.fromPgn('parity', kCrossAppParityPgn);

  test('every ply resolves to the same classification badge', () {
    expect(
      chesseverClassificationsFromMainline(game),
      kCrossAppParityClassifications,
    );
  });

  test('clocks and evals survive the shared comment format', () {
    for (var ply = 0; ply < kCrossAppParityClocks.length; ply++) {
      expect(
        game.mainline[ply].clockTime,
        kCrossAppParityClocks[ply],
        reason: 'clock on ply $ply',
      );
      expect(
        game.mainline[ply].eval,
        kCrossAppParityEvals[ply],
        reason: 'eval on ply $ply',
      );
    }
  });

  test('prose survives beside the machine tags', () {
    final comments = game.mainline[6].comments ?? const <String>[];
    final prose = comments.map(cleanPgnCommentText).where((c) => c.isNotEmpty);
    expect(prose, contains('A real comment.'));
  });

  test('the badge speaks for the verdict — no duplicate glyph, no raw code', () {
    // Both apps hide the standard NAG behind the classification badge and never
    // render the $240–$247 codes. If either changed, the same move would show a
    // chip on one app and a `!!` on the other.
    for (var ply = 0; ply < kCrossAppParityClassifications.length; ply++) {
      expect(
        mergeMoveNags(pgnNags: game.mainline[ply].nags, userNags: const []),
        isEmpty,
        reason: 'ply $ply must render as a badge only',
      );
    }
  });

  // NOT asserted here: a ply where the reader has ALSO applied their own
  // quality NAG. Mobile shows the reader's mark, desktop shows the report's
  // badge — both deliberate, both covered by their own suites. That is local
  // state, not something a pasted PGN carries, so it cannot make the same
  // pasted game look different on the two apps.
}
