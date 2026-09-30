import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:chessever2/theme/app_colors.dart';
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
/// The colours below track the gradient top stop of each badge SVG. They are
/// theme-independent: fills, graph markers and share renderers use them as
/// is, and so does text on the dark theme. Text that may land on the light
/// theme (the SAN in the notation list, recap counters) goes through
/// [moveAnnotationInk] instead.
Color moveAnnotationColor(LichessMoveAnnotationType type) => switch (type) {
  LichessMoveAnnotationType.brilliant => const Color(0xFF0FB4E5),
  LichessMoveAnnotationType.goodMove => const Color(0xFF26408B),
  LichessMoveAnnotationType.bestMove => const Color(0xFF1E924D),
  // Missed win: warm coral-red so it separates from pure-red blunder (??).
  LichessMoveAnnotationType.missedWin => const Color(0xFFE8331A),
  LichessMoveAnnotationType.inaccuracy => const Color(0xFFC47335),
  // Mistake (?): pre–Archive-7 orange so it is not a third red next to
  // missed win / blunder.
  LichessMoveAnnotationType.mistake => const Color(0xFFC55A1E),
  LichessMoveAnnotationType.blunder => const Color(0xFFF70400),
  LichessMoveAnnotationType.bookMove => const Color(0xFFB4A472),
  LichessMoveAnnotationType.forced => const Color(0xFF4E5B4F),
};

/// [moveAnnotationColor] as TEXT ink for the active theme.
///
/// Dark returns the badge palette untouched. On the light theme's paper most
/// of the palette misses AA as text: brilliant cyan and book about 2:1,
/// inaccuracy 3:1, best green (#1E924D) 3.3:1, missed win and blunder 3.5:1,
/// mistake orange (#C55A1E) 3.6:1. Light swaps in the same hue darkened to at
/// least 4.6:1 on the background (5.2:1 on the surface). Badge fills, graph
/// markers and share renderers keep reading [moveAnnotationColor]; only
/// text/icon tints should come through here.
Color moveAnnotationInk(BuildContext context, LichessMoveAnnotationType type) {
  if (!context.isLightTheme) return moveAnnotationColor(type);
  return switch (type) {
    LichessMoveAnnotationType.brilliant => const Color(0xFF09708F),
    LichessMoveAnnotationType.goodMove => const Color(0xFF26408B),
    LichessMoveAnnotationType.bestMove => const Color(0xFF18773E),
    LichessMoveAnnotationType.missedWin => const Color(0xFFC52914),
    LichessMoveAnnotationType.inaccuracy => const Color(0xFF965829),
    LichessMoveAnnotationType.mistake => const Color(0xFFA84D1A),
    LichessMoveAnnotationType.blunder => const Color(0xFFD30300),
    LichessMoveAnnotationType.bookMove => const Color(0xFF73663D),
    LichessMoveAnnotationType.forced => const Color(0xFF4E5B4F),
  };
}

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

/// [classificationColor] as TEXT ink for the active theme; see
/// [moveAnnotationInk].
Color classificationInk(
  BuildContext context,
  GameMoveClassification classification,
) => moveAnnotationInk(context, annotationTypeForClassification(classification));

/// Standard PGN quality NAG (`$1`–`$6`) → the classification whose badge stands
/// for that glyph.
///
/// This is the bridge between the two ways a move gets a verdict. A report
/// produces a [GameMoveClassification]; a reader tapping Annotate produces a
/// NAG. Both must land on the same badge, so `!` drawn by hand is the same
/// mark as `!` earned from analysis — on the board, in the notation list, and
/// in the PGN the move is exported to.
///
/// Two of the picker's quality glyphs are deliberately absent:
/// - `$5` (`!?`) — the classification set has no "interesting/speculative"
///   class and no asset for one, and folding it into `goodMove` would draw a
///   `!` badge over a `!?` move.
/// - `$7` (`□`, only move) — `forced_move.svg` is a circular live-annotation
///   mark, not one of the rounded-square report badges, and forced says
///   *how many* moves there were, not how good this one was.
///
/// Both keep rendering as their Unicode glyph, which is the honest answer.
const Map<int, GameMoveClassification> kQualityNagClassifications =
    <int, GameMoveClassification>{
      1: GameMoveClassification.goodMove, // !
      2: GameMoveClassification.mistake, // ?
      3: GameMoveClassification.brilliant, // !!
      4: GameMoveClassification.blunder, // ??
      6: GameMoveClassification.inaccuracy, // ?!
    };

/// The classification a quality NAG stands for, or null when the glyph has no
/// badge of its own (`$5`, `$7`, and every non-quality NAG).
GameMoveClassification? classificationForQualityNag(int nag) =>
    kQualityNagClassifications[nag];

/// The badge type for a quality NAG — [classificationForQualityNag] resolved
/// through to the annotation type the SVG/colour maps are keyed by.
LichessMoveAnnotationType? annotationTypeForQualityNag(int nag) {
  final classification = classificationForQualityNag(nag);
  return classification == null
      ? null
      : annotationTypeForClassification(classification);
}

/// The first NAG in [nags] that carries a classification badge.
///
/// Order is the caller's priority order, so a merged list that puts the
/// reader's own glyph first resolves to the reader's badge.
int? firstBadgedQualityNag(Iterable<int> nags) {
  for (final nag in nags) {
    if (kQualityNagClassifications.containsKey(nag)) return nag;
  }
  return null;
}
