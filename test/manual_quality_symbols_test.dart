import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const expected = {
    242: (GameMoveClassification.bestMove, 'assets/svgs/best.svg'),
    243: (GameMoveClassification.missedWin, 'assets/svgs/missed_win.svg'),
    247: (GameMoveClassification.bookMove, 'assets/svgs/book.svg'),
  };
  for (final entry in expected.entries) {
    test('manual ${entry.key} uses the existing quality badge', () {
      expect(manualQualityNags, contains(entry.key));
      expect(getNagDisplay(entry.key)?.category, NagCategory.quality);
      expect(classificationForQualityNag(entry.key), entry.value.$1);
      expect(
        annotationTypeForQualityNag(entry.key)?.iconAssetPath,
        entry.value.$2,
      );
      expect(qualityNagsSuppressLichess([entry.key, 14]), isTrue);
      expect(firstBadgedQualityNag([14, entry.key]), entry.key);
      expect(primaryBoardNag([14, entry.key]), entry.key);
      expect(mergeMoveNags(pgnNags: [1, 14], userNags: [entry.key]), [
        14,
        entry.key,
      ]);
    });
    test('manual ${entry.key} replaces old verdict on PGN export', () {
      final game = ChessGame.fromPgn(
        'manual',
        '[Event "Manual"]\n[Result "*"]\n\n1. e4 \$2 \$245 \$14 e5 *',
      );
      final merged = mergeUserMoveNagsForExport(game, {
        '0': [entry.key],
      });
      final nags = merged.mainline.first.nags!;
      expect(nags, containsAll([entry.key, 14]));
      expect(nags, isNot(contains(2)));
      expect(nags, isNot(contains(245)));
      expect(nags.where((n) => n == entry.key).length, 1);
      expect(classificationFromNags(nags), entry.value.$1);
      final restored = ChessGame.fromPgn('restored', exportGameToPgn(merged));
      expect(
        classificationFromNags(restored.mainline.first.nags),
        entry.value.$1,
      );
      if (entry.key == 247) {
        expect(nags, isNot(contains(1)));
        expect(nags, isNot(contains(3)));
      }
    });
  }
  test(
    'evaluation does not suppress classification and old options remain',
    () {
      expect(qualityNagsSuppressLichess([14, 146]), isFalse);
      expect(manualQualityNags, containsAll([1, 2, 3, 4, 5, 6, 7]));
      expect(manualQualityNags.toSet().length, manualQualityNags.length);
    },
  );

  test('every quality option is named, and verdict codes stay badge-only', () {
    for (final nag in manualQualityNags) {
      expect(qualityNagName(nag), isNotNull, reason: 'NAG $nag');
    }
    expect(qualityNagName(242), 'Best move');
    expect(qualityNagName(243), 'Missed win');
    expect(qualityNagName(247), 'Book move');
    // Exported PGNs carry these on many moves; plain-text notation (the
    // Gamebase explorer) must not glue "Book" or an emoji onto the SAN.
    for (final nag in [240, 241, 242, 243, 244, 245, 246, 247]) {
      expect(nagShownAsText(nag), isFalse, reason: 'NAG $nag');
    }
    for (final nag in [1, 2, 3, 4, 5, 6, 7, 14, 146]) {
      expect(nagShownAsText(nag), isTrue, reason: 'NAG $nag');
    }
  });
}
