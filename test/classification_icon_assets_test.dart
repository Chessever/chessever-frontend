import 'dart:io';

import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

/// Report-analysis classification set (eight badges from Archive 7).
/// Forced is live-annotation only and intentionally excluded.
const _reportClassifications = <GameMoveClassification>[
  GameMoveClassification.brilliant,
  GameMoveClassification.missedWin,
  GameMoveClassification.mistake,
  GameMoveClassification.blunder,
  GameMoveClassification.inaccuracy,
  GameMoveClassification.goodMove,
  GameMoveClassification.bestMove,
  GameMoveClassification.bookMove,
];

/// First `stop-color` in the SVG is the badge gradient top (source of truth).
Color _gradientTopFromSvg(String assetPath) {
  final body = File(assetPath).readAsStringSync();
  final match = RegExp(
    r'stop-color="#([0-9A-Fa-f]{6})"',
  ).firstMatch(body);
  expect(
    match,
    isNotNull,
    reason: '$assetPath must declare a linearGradient stop-color',
  );
  final hex = int.parse(match!.group(1)!, radix: 16);
  return Color(0xFF000000 | hex);
}

void main() {
  group('classification icon asset map', () {
    test('maps every report classification to a no-move SVG path', () {
      final expected = <GameMoveClassification, String>{
        GameMoveClassification.brilliant: 'assets/svgs/brilliant.svg',
        GameMoveClassification.missedWin: 'assets/svgs/missed_win.svg',
        GameMoveClassification.mistake: 'assets/svgs/mistake.svg',
        GameMoveClassification.blunder: 'assets/svgs/blunder.svg',
        GameMoveClassification.inaccuracy: 'assets/svgs/inaccuracy.svg',
        GameMoveClassification.goodMove: 'assets/svgs/good.svg',
        GameMoveClassification.bestMove: 'assets/svgs/best.svg',
        GameMoveClassification.bookMove: 'assets/svgs/book.svg',
      };

      for (final classification in _reportClassifications) {
        final path = classificationIconAsset(classification);
        expect(
          path,
          expected[classification],
          reason: '$classification must resolve via the shipped path map',
        );
        final basename = path.split('/').last;
        // Filenames must omit the token "move" (good.svg not good_move.svg).
        // Match whole path segments / underscore tokens, not substrings of
        // unrelated words.
        expect(
          basename.split(RegExp(r'[_.]')).contains('move'),
          isFalse,
          reason:
              'classification asset filename must not contain token "move": $path',
        );
        expect(path.endsWith('.svg'), isTrue);
      }
    });

    test('moveAnnotationIconAsset agrees with classificationIconAsset', () {
      for (final classification in _reportClassifications) {
        final viaClassification = classificationIconAsset(classification);
        final viaAnnotation = moveAnnotationIconAsset(
          annotationTypeForClassification(classification),
        );
        expect(viaClassification, viaAnnotation);
      }
    });

    test('good / best / book no longer use *_move.svg paths', () {
      expect(
        moveAnnotationIconAsset(LichessMoveAnnotationType.goodMove),
        'assets/svgs/good.svg',
      );
      expect(
        moveAnnotationIconAsset(LichessMoveAnnotationType.bestMove),
        'assets/svgs/best.svg',
      );
      expect(
        moveAnnotationIconAsset(LichessMoveAnnotationType.bookMove),
        'assets/svgs/book.svg',
      );
      expect(
        moveAnnotationIconAsset(LichessMoveAnnotationType.forced),
        'assets/svgs/forced_move.svg',
        reason: 'forced is out of Archive 7; keep existing forced asset',
      );
    });

    test('every mapped classification asset file exists on disk', () {
      for (final classification in _reportClassifications) {
        final assetPath = classificationIconAsset(classification);
        final file = File(assetPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'missing asset for $classification: $assetPath',
        );
        final body = file.readAsStringSync();
        expect(body.contains('<svg'), isTrue);
        // New Archive 7 badges use a linearGradient rounded-square fill.
        expect(
          body.contains('linearGradient') || body.contains('url(#'),
          isTrue,
          reason: '$assetPath should be a self-contained gradient badge',
        );
      }
    });

    test(
      'classificationColor matches icon SVG gradient top (source of truth)',
      () {
        for (final classification in _reportClassifications) {
          final assetPath = classificationIconAsset(classification);
          final fromIcon = _gradientTopFromSvg(assetPath);
          final fromPalette = classificationColor(classification);
          expect(
            fromPalette,
            fromIcon,
            reason:
                '$classification palette ${fromPalette.toARGB32().toRadixString(16)} '
                'must equal SVG top ${fromIcon.toARGB32().toRadixString(16)} '
                'in $assetPath',
          );
        }
      },
    );

    test('mistake badge restores pre–Archive-7 orange #C55A1E', () {
      final svgTop = _gradientTopFromSvg(
        classificationIconAsset(GameMoveClassification.mistake),
      );
      expect(
        svgTop,
        const Color(0xFFC55A1E),
        reason: 'mistake (?) must keep the previous orange disc, not wine red',
      );
      expect(
        classificationColor(GameMoveClassification.mistake),
        svgTop,
      );
    });

    test(
      'mistake / missedWin / blunder tops are pairwise distinct and match palette',
      () {
        final mistakePath = classificationIconAsset(
          GameMoveClassification.mistake,
        );
        final missedPath = classificationIconAsset(
          GameMoveClassification.missedWin,
        );
        final blunderPath = classificationIconAsset(
          GameMoveClassification.blunder,
        );

        final mistakeTop = _gradientTopFromSvg(mistakePath);
        final missedTop = _gradientTopFromSvg(missedPath);
        final blunderTop = _gradientTopFromSvg(blunderPath);

        expect(mistakeTop, const Color(0xFFC55A1E));
        expect(
          mistakeTop,
          isNot(missedTop),
          reason: 'mistake orange must not match missed-win red',
        );
        expect(
          mistakeTop,
          isNot(blunderTop),
          reason: 'mistake orange must not match blunder red',
        );
        expect(
          missedTop,
          isNot(blunderTop),
          reason:
              'missedWin and blunder must stay distinguishable pure/coral reds',
        );

        expect(
          classificationColor(GameMoveClassification.mistake),
          mistakeTop,
        );
        expect(
          classificationColor(GameMoveClassification.missedWin),
          missedTop,
        );
        expect(
          classificationColor(GameMoveClassification.blunder),
          blunderTop,
        );
        expect(
          moveAnnotationColor(LichessMoveAnnotationType.mistake),
          mistakeTop,
        );
        expect(
          moveAnnotationColor(LichessMoveAnnotationType.missedWin),
          missedTop,
        );
        expect(
          moveAnnotationColor(LichessMoveAnnotationType.blunder),
          blunderTop,
        );
      },
    );

    test('quality NAG text colors track the same classification palette', () {
      expect(
        getNagDisplay(1)!.color,
        moveAnnotationColor(LichessMoveAnnotationType.goodMove),
      );
      expect(
        getNagDisplay(2)!.color,
        moveAnnotationColor(LichessMoveAnnotationType.mistake),
      );
      expect(
        getNagDisplay(3)!.color,
        moveAnnotationColor(LichessMoveAnnotationType.brilliant),
      );
      expect(
        getNagDisplay(4)!.color,
        moveAnnotationColor(LichessMoveAnnotationType.blunder),
      );
      expect(
        getNagDisplay(6)!.color,
        moveAnnotationColor(LichessMoveAnnotationType.inaccuracy),
      );
      expect(
        getNagDisplay(7)!.color,
        moveAnnotationColor(LichessMoveAnnotationType.forced),
      );
    });
  });
}
