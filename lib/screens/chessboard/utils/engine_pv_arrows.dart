import 'package:chessever2/screens/chessboard/provider/board_eval_restart_policy.dart';
import 'package:chessever2/screens/chessboard/utils/engine_pv_palette.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

/// Width/head ramp by engine rank. chessground maps [Arrow.scale] to both
/// shaft width and arrowhead size, so this is the only lever for thickness.
/// Range must stay in (0, 1].
const List<double> kEngineArrowRankScales = <double>[
  1.0,
  0.85,
  0.70,
  0.55,
  0.40,
];

const List<double> kEngineArrowRankAlphas = <double>[
  0.95,
  0.78,
  0.62,
  0.48,
  0.34,
];

/// Default shaft color when every recommendation uses the same hue and rank
/// is shown only through opacity/scale (analysis-board "best move" path).
const Color kEngineArrowUniformBaseColor = Color(0xFF98B39A);

const Color kEngineArrowThreatsBaseColor = Color(0xFFFF0000);

/// How ranked recommendation arrows pick their base hue.
enum EngineArrowColorMode {
  /// One green for every line; rank is opacity + scale only.
  uniformRanked,

  /// Green / blue / orange / pink / purple — matches engine-line chrome.
  variantPalette,
}

/// Settings → Engine Experience → Show Arrows, applied the same way on every
/// analysis surface (game board, Opening Explorer, …).
///
/// Engine arrows stay off when analysis itself is off, the switch is off, or
/// a PV preview is walking the line (the board no longer shows the eval root).
bool shouldDrawEnginePvArrows({
  required bool showEngineAnalysis,
  required bool showPvArrows,
  bool isPvPreviewActive = false,
}) {
  return showEngineAnalysis && showPvArrows && !isPvPreviewActive;
}

double engineArrowScaleForRank(int index) {
  if (index >= 0 && index < kEngineArrowRankScales.length) {
    return kEngineArrowRankScales[index];
  }
  return kEngineArrowRankScales.last;
}

Color engineArrowColorForRank(Color baseColor, int index) {
  final alpha =
      index >= 0 && index < kEngineArrowRankAlphas.length
          ? kEngineArrowRankAlphas[index]
          : kEngineArrowRankAlphas.last;
  return baseColor.withValues(alpha: alpha);
}

Color engineArrowBaseColorForRank({
  required int index,
  required EngineArrowColorMode colorMode,
  bool isThreatsMode = false,
  Color? uniformBaseColor,
}) {
  if (isThreatsMode) return kEngineArrowThreatsBaseColor;
  if (colorMode == EngineArrowColorMode.variantPalette) {
    return enginePvVariantBaseColor(index);
  }
  return uniformBaseColor ?? kEngineArrowUniformBaseColor;
}

/// First-move arrows for ranked engine lines, capped by [maxArrows].
///
/// [legalForFen], when set, drops stale / opposite-side UCI so a leftover
/// eval cannot paint on the wrong position.
List<Shape> buildEnginePvArrows({
  required List<String> firstMoveUcis,
  required int maxArrows,
  String? legalForFen,
  bool isThreatsMode = false,
  EngineArrowColorMode colorMode = EngineArrowColorMode.variantPalette,
  Color? uniformBaseColor,
}) {
  if (maxArrows <= 0 || firstMoveUcis.isEmpty) return const <Shape>[];

  final arrows = <Shape>[];
  final limit =
      maxArrows < firstMoveUcis.length ? maxArrows : firstMoveUcis.length;

  for (var i = 0; i < limit; i++) {
    final token = firstMoveUcis[i]
        .trim()
        .split(RegExp(r'\s+'))
        .firstWhere((part) => part.isNotEmpty, orElse: () => '');
    if (token.isEmpty || token.contains('@')) continue;
    if (token.length < 4 || token.length > 5) continue;

    try {
      final move = NormalMove.fromUci(token);
      if (move.from == move.to) continue;
      if (legalForFen != null && !isFirstUciLegalForFen(legalForFen, token)) {
        continue;
      }

      arrows.add(
        Arrow(
          color: engineArrowColorForRank(
            engineArrowBaseColorForRank(
              index: i,
              colorMode: colorMode,
              isThreatsMode: isThreatsMode,
              uniformBaseColor: uniformBaseColor,
            ),
            i,
          ),
          orig: move.from,
          dest: move.to,
          scale: engineArrowScaleForRank(i),
        ),
      );
    } catch (_) {
      continue;
    }
  }

  return arrows;
}

/// Surface-level policy: honor Show Arrows, hide during PV preview, and only
/// paint when [evalFen] is the same position as [boardFen].
Set<Shape> resolveEnginePvBoardArrows({
  required bool showEngineAnalysis,
  required bool showPvArrows,
  required bool isPvPreviewActive,
  required List<String> rankedFirstMoveUcis,
  required int maxArrows,
  required String boardFen,
  required String evalFen,
  bool isThreatsMode = false,
  EngineArrowColorMode colorMode = EngineArrowColorMode.variantPalette,
  Color? uniformBaseColor,
}) {
  if (!shouldDrawEnginePvArrows(
    showEngineAnalysis: showEngineAnalysis,
    showPvArrows: showPvArrows,
    isPvPreviewActive: isPvPreviewActive,
  )) {
    return const <Shape>{};
  }
  if (boardEvalNormalizeFen(boardFen) != boardEvalNormalizeFen(evalFen)) {
    return const <Shape>{};
  }
  return buildEnginePvArrows(
    firstMoveUcis: rankedFirstMoveUcis,
    maxArrows: maxArrows,
    legalForFen: boardFen,
    isThreatsMode: isThreatsMode,
    colorMode: colorMode,
    uniformBaseColor: uniformBaseColor,
  ).toSet();
}
