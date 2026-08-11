import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trello #1047 — a move the reader annotates by hand must reach the same
/// place a report-classified move does: the badge on the board, the badge in
/// the notation list, and the NAGs in the PGN. Before this, a manual `!!` was
/// coloured text that lived in app state and died there — copy the PGN, share
/// it, sync it to desktop, render a GIF, and the annotation was simply gone.
void main() {
  group('quality NAG → classification badge', () {
    test('the five badged glyphs resolve to the report badge and asset', () {
      const expected = <int, GameMoveClassification>{
        1: GameMoveClassification.goodMove, // !
        2: GameMoveClassification.mistake, // ?
        3: GameMoveClassification.brilliant, // !!
        4: GameMoveClassification.blunder, // ??
        6: GameMoveClassification.inaccuracy, // ?!
      };
      expect(kQualityNagClassifications, expected);

      for (final entry in expected.entries) {
        expect(classificationForQualityNag(entry.key), entry.value);
        // Same asset a report verdict of that class would draw — one mark per
        // verdict, whoever made the call.
        expect(
          annotationTypeForQualityNag(entry.key)!.iconAssetPath,
          classificationIconAsset(entry.value),
        );
      }
    });

    test('!? and □ have no badge and stay text glyphs', () {
      // $5 has no "interesting" class (folding it into goodMove would draw a
      // `!` over a `!?` move) and $7 answers a different question entirely.
      for (final nag in const [5, 7]) {
        expect(classificationForQualityNag(nag), isNull);
        expect(annotationTypeForQualityNag(nag), isNull);
      }
      // Nor does anything outside the quality tier.
      for (final nag in const [10, 14, 16, 22, 32, 140, 146, 240, 247]) {
        expect(annotationTypeForQualityNag(nag), isNull);
      }
    });

    test('firstBadgedQualityNag reads the list in caller priority order', () {
      // Merged NAG lists are ordered reader-first, so this picks their glyph.
      expect(firstBadgedQualityNag(const [16, 2, 3]), 2);
      expect(firstBadgedQualityNag(const [14, 5, 7]), isNull);
      expect(firstBadgedQualityNag(const []), isNull);
    });
  });

  group('the reader out-ranks the PGN on the same move', () {
    test('their glyph replaces an imported verdict', () {
      // Without this the broadcast `!` (lower code) wins the badge slot and
      // the `?` they just applied never shows.
      expect(mergeMoveNags(pgnNags: const [1], userNags: const [2]), const [2]);
    });

    test('their glyph replaces a report classification carried in the PGN', () {
      expect(
        mergeMoveNags(pgnNags: const [3, 240], userNags: const [4]),
        const [4],
      );
    });

    test('an evaluation glyph of theirs displaces nothing', () {
      // `±` says who stands better, not how good the move was.
      expect(mergeMoveNags(pgnNags: const [1], userNags: const [16]), const [
        1,
        16,
      ]);
    });

    test('positional and observation NAGs survive their quality glyph', () {
      expect(
        mergeMoveNags(pgnNags: const [1, 14, 146], userNags: const [4]),
        const [14, 146, 4],
      );
    });
  });

  group('manual evals hydrate the PGN', () {
    ChessGame gameWithNags(Map<String, List<int>> nags) =>
        mergeUserMoveNagsForExport(
          ChessGame.fromPgn('manual', r'1. e4 e5 2. Nf3 Nc6 *'),
          nags,
        );

    test('a hand-applied glyph writes the standard NAG and the block code', () {
      final hydrated = gameWithNags({
        '0': [3], // !!
        '1': [6], // ?!
        '3': [2], // ?
      });

      expect(hydrated.mainline[0].nags, const [3, 240]);
      expect(hydrated.mainline[1].nags, const [6, 244]);
      expect(hydrated.mainline[2].nags, isNull);
      expect(hydrated.mainline[3].nags, const [2, 245]);

      final pgn = exportGameToPgn(hydrated);
      expect(pgn, contains(RegExp(r'e4 \$3 \$240\b')));
      expect(pgn, contains(RegExp(r'e5 \$6 \$244\b')));
      expect(pgn, contains(RegExp(r'Nc6 \$2 \$245\b')));
    });

    test('!? and □ travel as their standard NAG alone', () {
      final hydrated = gameWithNags({
        '0': [5],
        '1': [7],
      });
      expect(hydrated.mainline[0].nags, const [5]);
      expect(hydrated.mainline[1].nags, const [7]);
      expect(
        hydrated.mainline[0].nags!.where(isChesseverClassificationNag),
        isEmpty,
      );
    });

    test('evaluation and observation glyphs merge in beside the rest', () {
      final hydrated = gameWithNags({
        '0': [16, 146],
      });
      expect(hydrated.mainline[0].nags, const [16, 146]);
    });

    test('their verdict replaces the one already on the move', () {
      final source = ChessGame.fromPgn('manual-over', r'1. e4 $6 $14 e5 *');
      final hydrated = mergeUserMoveNagsForExport(source, {
        '0': [3],
      });
      // Imported `?!` and its block code go; `⩲` stays.
      expect(hydrated.mainline[0].nags, const [14, 3, 240]);
      expect(
        hydrated.mainline[0].nags!.where(isChesseverClassificationNag).length,
        1,
      );
    });

    test('a report verdict is overruled, not stacked beside', () {
      final source = ChessGame.fromPgn('manual-vs-report', r'1. e4 e5 *');
      final report = GameAnalysisReport(
        fingerprint: gameReportFingerprint(source),
        positions: const [],
        moves: const [
          GameReportMove(
            ply: 1,
            san: 'e4',
            uci: 'e2e4',
            isWhite: true,
            classification: GameMoveClassification.bestMove,
            evaluation: GameReportLine(
              moves: ['e2e4'],
              depth: 18,
              centipawns: 20,
            ),
          ),
        ],
        whiteAccuracy: 90,
        blackAccuracy: 90,
        generatedAt: DateTime.utc(2026, 8, 11),
      );

      final hydrated = hydrateGameAnnotationsForExport(
        source,
        report: report,
        userMoveNags: {
          '0': [4], // the reader disagrees: ??
        },
      );
      expect(hydrated.mainline[0].nags, const [4, 246]);
    });

    test('variations are annotated too', () {
      final source = ChessGame.fromPgn(
        'manual-variation',
        r'1. e4 e5 (1... c5 2. Nf3) 2. Nf3 *',
      );
      // A variation hangs off the move it branches from (1. e4), so its moves
      // are addressed `0-<variation>-<index>`: `0-0-0` is 1... c5.
      final hydrated = mergeUserMoveNagsForExport(source, {
        '0-0-0': [3],
        '0-0-1': [2],
      });

      final variation = hydrated.mainline[0].variations![0];
      expect(variation[0].nags, const [3, 240]);
      expect(variation[1].nags, const [2, 245]);
      // The move that owns the variation is untouched.
      expect(hydrated.mainline[0].nags, isNull);
      expect(exportGameToPgn(hydrated), contains(r'$240'));
    });

    test('an empty map and an unmatched pointer leave the game alone', () {
      final source = ChessGame.fromPgn('manual-noop', r'1. e4 e5 *');
      expect(
        mergeUserMoveNagsForExport(source, const <String, List<int>>{}),
        same(source),
      );
      expect(
        mergeUserMoveNagsForExport(source, {
          '9': [3],
        }),
        same(source),
      );
    });

    test('re-exporting an already hydrated game is a no-op', () {
      final nags = {
        '0': [3],
      };
      final once = gameWithNags(nags);
      final twice = mergeUserMoveNagsForExport(once, nags);
      expect(twice.mainline[0].nags, const [3, 240]);
      expect(exportGameToPgn(twice), exportGameToPgn(once));
    });

    test('another device reads the badge back off the PGN', () {
      // This is the whole point of the block code: `move_nags` is a ChessEver
      // column that never leaves, so without $240 the reopened game shows a
      // bare `!!` and no badge.
      final exported = exportGameToPgn(
        gameWithNags({
          '0': [3],
          '1': [2],
        }),
      );
      final reopened = ChessGame.fromPgn('manual-roundtrip', exported);

      expect(chesseverClassificationsFromMainline(reopened), {
        0: GameMoveClassification.brilliant,
        1: GameMoveClassification.mistake,
      });
      // …and it resolves to the same badge the reader tapped.
      expect(
        pgnClassificationAnnotations(reopened)[0]!.type,
        LichessMoveAnnotationType.brilliant,
      );
      expect(
        pgnClassificationAnnotations(reopened)[0]!.useClassificationIcon,
        isTrue,
      );
    });
  });
}
