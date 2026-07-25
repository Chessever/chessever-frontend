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
/// Each asset paints its own filled disc edge-to-edge, so callers render the
/// SVG directly and must not wrap it in a tinted circle. The colours below are
/// for *text* tinting (the SAN in the notation list, recap counters) and are
/// kept in step with the disc colour baked into each SVG.
Color moveAnnotationColor(LichessMoveAnnotationType type) => switch (type) {
  LichessMoveAnnotationType.brilliant => const Color(0xFF177A68),
  LichessMoveAnnotationType.goodMove => const Color(0xFF177A68),
  LichessMoveAnnotationType.bestMove => const Color(0xFF28833A),
  LichessMoveAnnotationType.missedWin => const Color(0xFF8F1E1E),
  LichessMoveAnnotationType.inaccuracy => const Color(0xFFD9900A),
  LichessMoveAnnotationType.mistake => const Color(0xFFC55A1E),
  LichessMoveAnnotationType.blunder => const Color(0xFFB52626),
  LichessMoveAnnotationType.bookMove => const Color(0xFF6B7A8A),
  LichessMoveAnnotationType.forced => const Color(0xFF4E5B4F),
};

String moveAnnotationIconAsset(LichessMoveAnnotationType type) =>
    switch (type) {
      LichessMoveAnnotationType.brilliant => 'assets/svgs/brilliant.svg',
      LichessMoveAnnotationType.goodMove => 'assets/svgs/good_move.svg',
      LichessMoveAnnotationType.bestMove => 'assets/svgs/best_move.svg',
      LichessMoveAnnotationType.missedWin => 'assets/svgs/missed_win.svg',
      LichessMoveAnnotationType.inaccuracy => 'assets/svgs/inaccuracy.svg',
      LichessMoveAnnotationType.mistake => 'assets/svgs/mistake.svg',
      LichessMoveAnnotationType.blunder => 'assets/svgs/blunder.svg',
      LichessMoveAnnotationType.bookMove => 'assets/svgs/book_move.svg',
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
