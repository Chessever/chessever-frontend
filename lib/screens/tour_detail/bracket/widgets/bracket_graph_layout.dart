import 'dart:math' as math;

import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../utils/knockout_stage_parser.dart';

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
    this.connections = const [],
  });

  final Size size;
  final Map<String, Rect> stageHeaderRects;
  final Map<String, Rect> matchRects;
  final List<BracketConnection> connections;

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

/// A displayed route. A planned route never counts as advancement evidence.
class BracketConnection {
  const BracketConnection({
    required this.sourceMatchKey,
    required this.destinationMatchKey,
    required this.isConfirmed,
    this.feedsLosers = false,
  });
  final String sourceMatchKey;
  final String destinationMatchKey;
  final bool isConfirmed;
  final bool feedsLosers;
}

/// Scene point to put at the viewport center when opening on [focusRect].
///
/// Centering on a card near the top of its column used to leave a band of
/// empty canvas above the stage header (the live first-round match sat in
/// the middle of the screen). When centering would push the header below
/// [topInset], the camera moves down until the header sits at [topInset];
/// targets deeper in a column already put the header above the screen and
/// keep their center.
Offset readableStageCameraCenter({
  required Rect focusRect,
  required Rect? headerRect,
  required Size viewport,
  required double scale,
  double topInset = 12,
}) {
  final center = focusRect.center;
  if (headerRect == null || scale <= 0 || viewport.isEmpty) return center;
  final minimumCenterY =
      headerRect.top + (viewport.height / 2 - topInset) / scale;
  if (center.dy >= minimumCenterY) return center;
  return Offset(center.dx, minimumCenterY);
}

/// Places the full tree while keeping planned routes separate from evidence.
///
/// The first column is distributed evenly. A later card aligns to the average
/// center of both official feeders, or published incoming sources when no seed
/// route is known; otherwise it keeps its proportional feed-order position. A forward
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

  bool isThird(KnockoutStage stage) =>
      resolveLogicalKnockoutStage(stage.label, '')?.key == 'third-place';
  final finals = stages
      .where((s) => resolveLogicalKnockoutStage(s.label, '')?.key == 'finals')
      .toList();
  final placements = finals.isNotEmpty
      ? stages.where(isThird).toList()
      : <KnockoutStage>[];
  final mainStages = stages.where((s) => !placements.contains(s)).toList();
  final largestStage = mainStages.fold<int>(
    0,
    (largest, s) => math.max(largest, s.matches.length),
  );
  final contentHeight = math.max(
    BracketGraphMetrics.minimumContentHeight,
    largestStage * BracketGraphMetrics.matchHeight +
        math.max(0, largestStage - 1) * BracketGraphMetrics.matchGap,
  );
  var canvasBottom = BracketGraphMetrics.contentTop + contentHeight;
  final stageHeaderRects = <String, Rect>{};
  final matchRects = <String, Rect>{};
  final incomingSources = <String, List<String>>{};
  for (final edge in bracket.edges) {
    incomingSources
        .putIfAbsent(edge.destinationMatchKey, () => [])
        .add(edge.sourceMatchKey);
  }
  for (var column = 0; column < mainStages.length; column++) {
    final stage = mainStages[column];
    final x =
        BracketGraphMetrics.canvasPadding +
        column * BracketGraphMetrics.stageStride;
    stageHeaderRects[stage.key] = Rect.fromLTWH(
      x,
      BracketGraphMetrics.headerTop,
      BracketGraphMetrics.matchWidth,
      BracketGraphMetrics.headerHeight,
    );
    final desired = <double>[];
    for (var index = 0; index < stage.matches.length; index++) {
      final match = stage.matches[index];
      // Both feeders determine a reserved slot's position, including the one
      // that has not played. Qualifying a player cannot move the bracket.
      final feeders = match.feederMatchKeys.isNotEmpty
          ? match.feederMatchKeys
          : incomingSources[match.key] ?? const <String>[];
      final centers = feeders
          .map((key) => matchRects[key]?.center.dy)
          .whereType<double>()
          .toList();
      final center = centers.isNotEmpty
          ? centers.reduce((a, b) => a + b) / centers.length
          : BracketGraphMetrics.contentTop +
                ((index + 0.5) / stage.matches.length) * contentHeight;
      desired.add(center - BracketGraphMetrics.matchHeight / 2);
    }
    final tops = _spaceCards(
      desired,
      contentTop: BracketGraphMetrics.contentTop,
      contentBottom: BracketGraphMetrics.contentTop + contentHeight,
    );
    for (var index = 0; index < stage.matches.length; index++) {
      matchRects[stage.matches[index].key] = Rect.fromLTWH(
        x,
        tops[index],
        BracketGraphMetrics.matchWidth,
        BracketGraphMetrics.matchHeight,
      );
    }
  }
  // Third place hangs below the final, outside the title path. It never takes
  // an intervening column or shifts the final away from its semifinal feeders.
  for (final stage in placements) {
    final finalStage = finals.first;
    final x = stageHeaderRects[finalStage.key]!.left;
    var top =
        finalStage.matches
            .map((m) => matchRects[m.key]?.bottom ?? 0)
            .fold<double>(
              BracketGraphMetrics.contentTop + contentHeight / 2,
              math.max,
            ) +
        56;
    stageHeaderRects[stage.key] = Rect.fromLTWH(
      x,
      top,
      BracketGraphMetrics.matchWidth,
      BracketGraphMetrics.headerHeight,
    );
    top += BracketGraphMetrics.headerHeight + BracketGraphMetrics.headerGap;
    for (final match in stage.matches) {
      matchRects[match.key] = Rect.fromLTWH(
        x,
        top,
        BracketGraphMetrics.matchWidth,
        BracketGraphMetrics.matchHeight,
      );
      top += BracketGraphMetrics.matchHeight + BracketGraphMetrics.matchGap;
    }
    canvasBottom = math.max(canvasBottom, top);
  }
  final evidence = {
    for (final e in bracket.edges)
      '${e.sourceMatchKey}\u0000${e.destinationMatchKey}',
  };
  final connections = <String, BracketConnection>{};
  for (final stage in stages) {
    for (final match in stage.matches) {
      for (final source in match.feederMatchKeys) {
        final key = '$source\u0000${match.key}';
        connections[key] = BracketConnection(
          sourceMatchKey: source,
          destinationMatchKey: match.key,
          isConfirmed: evidence.contains(key),
          feedsLosers: match.feedsLosers,
        );
      }
    }
  }
  for (final edge in bracket.edges) {
    final key = '${edge.sourceMatchKey}\u0000${edge.destinationMatchKey}';
    connections.putIfAbsent(
      key,
      () => BracketConnection(
        sourceMatchKey: edge.sourceMatchKey,
        destinationMatchKey: edge.destinationMatchKey,
        isConfirmed: true,
        feedsLosers: placements.any(
          (s) => s.matches.any((m) => m.key == edge.destinationMatchKey),
        ),
      ),
    );
  }
  return BracketGraphLayout(
    size: Size(
      BracketGraphMetrics.canvasPadding * 2 +
          mainStages.length * BracketGraphMetrics.matchWidth +
          math.max(0, mainStages.length - 1) * BracketGraphMetrics.stageGap,
      canvasBottom + BracketGraphMetrics.bottomPadding,
    ),
    stageHeaderRects: Map.unmodifiable(stageHeaderRects),
    matchRects: Map.unmodifiable(matchRects),
    connections: List.unmodifiable(connections.values),
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
