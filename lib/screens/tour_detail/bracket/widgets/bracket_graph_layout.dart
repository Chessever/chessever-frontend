import 'dart:math' as math;

import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:flutter/material.dart';

/// Fixed logical measurements for the bracket canvas.
///
/// The canvas is zoomed as a whole, so keeping these values independent from
/// the device width gives cards a stable, readable size at a 1x camera scale.
abstract final class BracketGraphMetrics {
  static const double canvasPadding = 24;
  static const double headerTop = 18;
  static const double headerHeight = 28;
  static const double headerGap = 16;
  static const double matchWidth = 220;
  static const double matchHeight = 92;
  static const double matchGap = 18;
  static const double stageGap = 72;
  static const double bottomPadding = 32;
  static const double minimumContentHeight = 330;

  static double get contentTop => headerTop + headerHeight + headerGap;
  static double get stageStride => matchWidth + stageGap;
}

@immutable
class BracketGraphLayout {
  const BracketGraphLayout({
    required this.size,
    required this.stageHeaderRects,
    required this.matchRects,
  });

  final Size size;
  final Map<String, Rect> stageHeaderRects;
  final Map<String, Rect> matchRects;

  Rect? matchRect(String matchKey) => matchRects[matchKey];

  /// A compact camera target for a stage.
  ///
  /// Large early rounds intentionally return a viewport-sized slice around
  /// their first live card (or middle card). Initial focus must remain
  /// readable; fitting an entire 64-player column would make its text tiny.
  Rect? readableFocusRectForStage(KnockoutStage stage) {
    if (stage.matches.isEmpty) return stageHeaderRects[stage.key];

    final liveIndex = stage.matches.indexWhere((match) => match.isLive);
    final targetIndex = liveIndex >= 0 ? liveIndex : stage.matches.length ~/ 2;
    final target = matchRects[stage.matches[targetIndex].key];
    if (target == null) return stageHeaderRects[stage.key];

    return Rect.fromCenter(
      center: Offset(target.center.dx, target.center.dy - 28),
      width: BracketGraphMetrics.matchWidth + 32,
      height: 360,
    );
  }
}

/// Places stage columns and match cards without inferring any missing edges.
///
/// The first column is distributed evenly. A later card is aligned to the
/// average center of its *published* incoming source cards when those edges
/// exist; otherwise it keeps its proportional feed-order position. A forward
/// and backward spacing pass then preserves feed order and prevents overlap.
BracketGraphLayout buildBracketGraphLayout(KnockoutBracket bracket) {
  final stages = List<KnockoutStage>.of(bracket.stages)
    ..sort((a, b) => a.order.compareTo(b.order));

  if (stages.isEmpty) {
    return const BracketGraphLayout(
      size: Size(
        BracketGraphMetrics.matchWidth + BracketGraphMetrics.canvasPadding * 2,
        BracketGraphMetrics.minimumContentHeight,
      ),
      stageHeaderRects: <String, Rect>{},
      matchRects: <String, Rect>{},
    );
  }

  final largestStage = stages.fold<int>(
    0,
    (largest, stage) => math.max(largest, stage.matches.length),
  );
  final packedHeight =
      largestStage <= 0
          ? BracketGraphMetrics.minimumContentHeight
          : largestStage * BracketGraphMetrics.matchHeight +
              math.max(0, largestStage - 1) * BracketGraphMetrics.matchGap;
  final contentHeight = math.max(
    BracketGraphMetrics.minimumContentHeight,
    packedHeight,
  );
  final canvasHeight =
      BracketGraphMetrics.contentTop +
      contentHeight +
      BracketGraphMetrics.bottomPadding;
  final canvasWidth =
      BracketGraphMetrics.canvasPadding * 2 +
      stages.length * BracketGraphMetrics.matchWidth +
      math.max(0, stages.length - 1) * BracketGraphMetrics.stageGap;

  final stageHeaderRects = <String, Rect>{};
  final matchRects = <String, Rect>{};
  final incomingSources = <String, List<String>>{};
  for (final edge in bracket.edges) {
    incomingSources
        .putIfAbsent(edge.destinationMatchKey, () => <String>[])
        .add(edge.sourceMatchKey);
  }

  for (var stageIndex = 0; stageIndex < stages.length; stageIndex += 1) {
    final stage = stages[stageIndex];
    final x =
        BracketGraphMetrics.canvasPadding +
        stageIndex * BracketGraphMetrics.stageStride;
    stageHeaderRects[stage.key] = Rect.fromLTWH(
      x,
      BracketGraphMetrics.headerTop,
      BracketGraphMetrics.matchWidth,
      BracketGraphMetrics.headerHeight,
    );

    final matchCount = stage.matches.length;
    if (matchCount == 0) continue;

    final desiredTop = <double>[];
    for (var matchIndex = 0; matchIndex < matchCount; matchIndex += 1) {
      final match = stage.matches[matchIndex];
      final sourceCenters = (incomingSources[match.key] ?? const <String>[])
          .map((key) => matchRects[key])
          .whereType<Rect>()
          .map((rect) => rect.center.dy)
          .toList(growable: false);

      final centerY =
          sourceCenters.isNotEmpty
              ? sourceCenters.reduce((a, b) => a + b) / sourceCenters.length
              : BracketGraphMetrics.contentTop +
                  ((matchIndex + 0.5) / matchCount) * contentHeight;
      desiredTop.add(centerY - BracketGraphMetrics.matchHeight / 2);
    }

    final placedTop = _spaceCards(
      desiredTop,
      contentTop: BracketGraphMetrics.contentTop,
      contentBottom: BracketGraphMetrics.contentTop + contentHeight,
    );
    for (var matchIndex = 0; matchIndex < matchCount; matchIndex += 1) {
      matchRects[stage.matches[matchIndex].key] = Rect.fromLTWH(
        x,
        placedTop[matchIndex],
        BracketGraphMetrics.matchWidth,
        BracketGraphMetrics.matchHeight,
      );
    }
  }

  return BracketGraphLayout(
    size: Size(canvasWidth, canvasHeight),
    stageHeaderRects: Map.unmodifiable(stageHeaderRects),
    matchRects: Map.unmodifiable(matchRects),
  );
}

List<double> _spaceCards(
  List<double> desiredTop, {
  required double contentTop,
  required double contentBottom,
}) {
  if (desiredTop.isEmpty) return const <double>[];

  final maximumTop = contentBottom - BracketGraphMetrics.matchHeight;
  final result = <double>[
    desiredTop.first.clamp(contentTop, maximumTop).toDouble(),
  ];
  final stride = BracketGraphMetrics.matchHeight + BracketGraphMetrics.matchGap;

  for (var index = 1; index < desiredTop.length; index += 1) {
    result.add(
      math
          .max(
            desiredTop[index].clamp(contentTop, maximumTop).toDouble(),
            result[index - 1] + stride,
          )
          .toDouble(),
    );
  }

  if (result.last > maximumTop) {
    result[result.length - 1] = maximumTop;
    for (var index = result.length - 2; index >= 0; index -= 1) {
      result[index] = math.min(result[index], result[index + 1] - stride);
    }
  }

  // The content height is sized from the largest stage, so this correction is
  // normally zero. It protects custom/test inputs from floating-point drift.
  if (result.first < contentTop) {
    final correction = contentTop - result.first;
    for (var index = 0; index < result.length; index += 1) {
      result[index] += correction;
    }
  }

  return result;
}
