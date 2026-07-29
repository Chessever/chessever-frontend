import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter/material.dart';

/// Canonical palette and asset map for move-classification badges.
///
/// The board badges, the notation chips and the Game Review recap all read from
/// here so the surfaces cannot drift apart — they previously did, with missed
/// win, mistake and blunder carrying different hexes on the board than in the
/// recap.
///
/// Each asset paints its own gradient rounded-square badge edge-to-edge, so
/// callers render the SVG directly and must not wrap it in a tinted circle.
/// The colours below are for *text* tinting (the SAN in the notation list,
/// recap counters) and track the gradient top stop of each badge SVG.
Color moveAnnotationColor(LichessMoveAnnotationType type) => switch (type) {
  LichessMoveAnnotationType.brilliant => const Color(0xFF0FB4E5),
  LichessMoveAnnotationType.goodMove => const Color(0xFF26408B),
  LichessMoveAnnotationType.bestMove => const Color(0xFF1E924D),
  // Missed win: warm coral-red so it separates from pure-red blunder (??).
  LichessMoveAnnotationType.missedWin => const Color(0xFFE8331A),
  LichessMoveAnnotationType.inaccuracy => const Color(0xFFC47335),
  LichessMoveAnnotationType.mistake => const Color(0xFFB20D30),
  LichessMoveAnnotationType.blunder => const Color(0xFFF70400),
  LichessMoveAnnotationType.bookMove => const Color(0xFFB4A472),
  LichessMoveAnnotationType.forced => const Color(0xFF4E5B4F),
};

String moveAnnotationIconAsset(LichessMoveAnnotationType type) =>
    switch (type) {
      LichessMoveAnnotationType.brilliant => 'assets/svgs/brilliant.svg',
      LichessMoveAnnotationType.goodMove => 'assets/svgs/good.svg',
      LichessMoveAnnotationType.bestMove => 'assets/svgs/best.svg',
      LichessMoveAnnotationType.missedWin => 'assets/svgs/missed_win.svg',
      LichessMoveAnnotationType.inaccuracy => 'assets/svgs/inaccuracy.svg',
      LichessMoveAnnotationType.mistake => 'assets/svgs/mistake.svg',
      LichessMoveAnnotationType.blunder => 'assets/svgs/blunder.svg',
      LichessMoveAnnotationType.bookMove => 'assets/svgs/book.svg',
      // Live-annotation only; not part of the report-classification set.
      LichessMoveAnnotationType.forced => 'assets/svgs/forced_move.svg',
    };

LichessMoveAnnotationType annotationTypeForClassification(
  GameMoveClassification classification,
) => switch (classification) {
  GameMoveClassification.brilliant => LichessMoveAnnotationType.brilliant,
  GameMoveClassification.goodMove => LichessMoveAnnotationType.goodMove,
  GameMoveClassification.bestMove => LichessMoveAnnotationType.bestMove,
  GameMoveClassification.missedWin => LichessMoveAnnotationType.missedWin,
  GameMoveClassification.inaccuracy => LichessMoveAnnotationType.inaccuracy,
  GameMoveClassification.mistake => LichessMoveAnnotationType.mistake,
  GameMoveClassification.blunder => LichessMoveAnnotationType.blunder,
  GameMoveClassification.bookMove => LichessMoveAnnotationType.bookMove,
};

String classificationIconAsset(GameMoveClassification classification) =>
    moveAnnotationIconAsset(annotationTypeForClassification(classification));

Color classificationColor(GameMoveClassification classification) =>
    moveAnnotationColor(annotationTypeForClassification(classification));
