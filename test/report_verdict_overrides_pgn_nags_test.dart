import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Broadcast PGNs come out of the Lichess database with move-quality NAGs
/// already baked in, and they come and go between snapshots. Once our own
/// report has judged a move, it owns the verdict for it — otherwise the same
/// move shows two contradicting answers at once (a yellow `?!` on the SAN next
/// to our Best badge), and which one the reader sees depends on nothing but
/// which PGN snapshot their phone happened to fetch.
void main() {
  group('report verdict displaces PGN move-quality NAGs', () {
    test('a judged move drops the PGN verdict glyphs', () {
      expect(
        mergeMoveNags(
          pgnNags: const [6],
          userNags: const [],
          reportJudgedMove: true,
        ),
        isEmpty,
      );
    });

    test('without a report the PGN verdict still renders', () {
      expect(
        mergeMoveNags(pgnNags: const [6], userNags: const []),
        const [6],
      );
    });

    test('evaluation and observation glyphs survive a report', () {
      // $16 (±) and $146 (N) describe the position and the idea, not how good
      // the move was, so they make no claim the report is answering.
      expect(
        mergeMoveNags(
          pgnNags: const [4, 16, 146],
          userNags: const [],
          reportJudgedMove: true,
        ),
        const [16, 146],
        reason: 'only the \$4 verdict gives way to the report',
      );
    });

    test('the reader\'s own annotations are never filtered', () {
      expect(
        mergeMoveNags(
          pgnNags: const [2],
          userNags: const [6],
          reportJudgedMove: true,
        ),
        const [6],
        reason:
            'an in-app NAG is the reader\'s explicit intent, so it outranks the '
            'report the same way it always outranked Lichess analysis',
      );
    });

    test('a PGN-carried classification displaces the verdict on its own', () {
      // A game synced from desktop has no local report, but its moves carry our
      // $240–$247 codes. That is the same claim a live report makes, so the
      // standard glyph beside it yields to the badge rather than doubling it.
      expect(
        mergeMoveNags(pgnNags: const [3, 240], userNags: const []),
        isEmpty,
      );
      expect(
        mergeMoveNags(pgnNags: const [4, 16, 243], userNags: const []),
        const [16],
        reason: 'the positional glyph answers a different question',
      );
      // The reader's own annotation still wins over ours.
      expect(
        mergeMoveNags(pgnNags: const [3, 240], userNags: const [2]),
        const [2],
      );
    });

    test('classification codes never render as glyphs', () {
      // $240–$247 are an identity for the badge, not something to draw. Even
      // with no report and no verdict beside them they must not reach the UI.
      expect(mergeMoveNags(pgnNags: const [247], userNags: const []), isEmpty);
      for (final nag in kChesseverClassificationNags.values) {
        expect(isChesseverClassificationNag(nag), isTrue);
        expect(
          mergeMoveNags(pgnNags: [nag, 16], userNags: const []),
          const [16],
        );
      }
    });

    test(r'$7 (only move) is not a quality verdict and stays', () {
      expect(kMoveVerdictNags, const {1, 2, 3, 4, 5, 6});
      expect(
        mergeMoveNags(
          pgnNags: const [7],
          userNags: const [],
          reportJudgedMove: true,
        ),
        const [7],
      );
    });
  });

  group('reportJudgedMainlineMove', () {
    test('an analysed move we left unlabelled still counts as judged', () {
      // The whole point: our silence on a move is a verdict, so Lichess must not
      // get to speak for it. Coverage is the gate, never "did we chip it".
      expect(
        reportJudgedMainlineMove(
          isMainline: true,
          moveIndex: 12,
          pointerIndex: null,
          reportedMoveCount: 40,
        ),
        isTrue,
      );
      expect(
        mergeMoveNags(
          pgnNags: const [2],
          userNags: const [],
          reportJudgedMove: true,
        ),
        isEmpty,
        reason:
            'a judged-but-unlabelled move shows nothing, not the imported "?"',
      );
    });

    test('no report means nothing is displaced', () {
      expect(
        reportJudgedMainlineMove(
          isMainline: true,
          moveIndex: 0,
          pointerIndex: null,
          reportedMoveCount: 0,
        ),
        isFalse,
      );
    });

    test('moves past the analysed mainline keep their PGN glyphs', () {
      // A live game grows while the report is frozen at the length it analysed.
      expect(
        reportJudgedMainlineMove(
          isMainline: true,
          moveIndex: 40,
          pointerIndex: null,
          reportedMoveCount: 40,
        ),
        isFalse,
      );
    });

    test('variations are never judged — the report only walks the mainline', () {
      expect(
        reportJudgedMainlineMove(
          isMainline: false,
          moveIndex: 3,
          pointerIndex: null,
          reportedMoveCount: 40,
        ),
        isFalse,
      );
    });

    test('falls back to the mainline pointer head when moveIndex is absent', () {
      expect(
        reportJudgedMainlineMove(
          isMainline: true,
          moveIndex: null,
          pointerIndex: 3,
          reportedMoveCount: 40,
        ),
        isTrue,
      );
      expect(
        reportJudgedMainlineMove(
          isMainline: true,
          moveIndex: null,
          pointerIndex: null,
          reportedMoveCount: 40,
        ),
        isFalse,
      );
    });
  });

  group('userNagsForMovePointer', () {
    test('reads only the in-app map, keyed by encoded pointer', () {
      final userNags = <String, List<int>>{
        '3': const [6],
      };
      expect(userNagsForMovePointer(const [3], userNags), const [6]);
      expect(userNagsForMovePointer(const [4], userNags), isEmpty);
      expect(userNagsForMovePointer(const [], userNags), isEmpty);
      expect(userNagsForMovePointer(null, userNags), isEmpty);
    });
  });

  group('Annotate quality NAG overrides report classification badge', () {
    const reportBadge = LichessMoveAnnotation(
      type: LichessMoveAnnotationType.bestMove,
      comment: '',
      useClassificationIcon: true,
    );

    test('report wins when the reader has no quality NAG', () {
      expect(
        resolveClassificationBadgeAnnotation(
          rawAnnotation: reportBadge,
          userNags: const [],
        ),
        reportBadge,
      );
      expect(
        resolveClassificationBadgeAnnotation(
          rawAnnotation: reportBadge,
          // Evaluation-only user NAG must not hide the report badge.
          userNags: const [16],
        ),
        reportBadge,
      );
    });

    test('user quality Annotate NAG hides the report badge', () {
      // Board already prefers user quality NAGs; notation must match.
      for (final nag in const [1, 2, 3, 4, 5, 6, 7]) {
        expect(
          resolveClassificationBadgeAnnotation(
            rawAnnotation: reportBadge,
            userNags: [nag],
          ),
          isNull,
          reason: 'user NAG \$$nag must override report classification icon',
        );
        expect(
          userQualityNagsOverrideClassification([nag]),
          isTrue,
        );
      }
    });

    test('clearing the user quality NAG restores the report badge', () {
      // Simulate Annotate toggle on then off: map entry → empty.
      final withOverride = resolveClassificationBadgeAnnotation(
        rawAnnotation: reportBadge,
        userNags: const [4], // ??
      );
      expect(withOverride, isNull);

      final afterClear = resolveClassificationBadgeAnnotation(
        rawAnnotation: reportBadge,
        userNags: const [],
      );
      expect(afterClear, reportBadge);
    });

    test(
      'merge keeps user quality NAG under a report so notation can render it',
      () {
        // mergeMoveNags strips PGN $2 but keeps the reader's $6; notation then
        // draws the user glyph and resolveClassificationBadgeAnnotation hides
        // the report badge.
        final merged = mergeMoveNags(
          pgnNags: const [2],
          userNags: const [6],
          reportJudgedMove: true,
        );
        expect(merged, const [6]);
        expect(qualityNagsSuppressLichess(merged), isTrue);
        expect(
          resolveClassificationBadgeAnnotation(
            rawAnnotation: reportBadge,
            userNags: const [6],
          ),
          isNull,
        );
      },
    );

    test('non-classification annotations are never promoted to a badge', () {
      const lichessOnly = LichessMoveAnnotation(
        type: LichessMoveAnnotationType.blunder,
        comment: 'from Lichess',
        useClassificationIcon: false,
      );
      expect(
        resolveClassificationBadgeAnnotation(
          rawAnnotation: lichessOnly,
          userNags: const [],
        ),
        isNull,
      );
    });
  });
}
