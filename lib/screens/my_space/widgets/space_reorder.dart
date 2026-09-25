import 'dart:math' as math;

import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:flutter/widgets.dart';

/// How a lifted tile may travel while it is being reordered.
enum SpaceReorderAxis {
  /// Along a rail: the tile follows the finger sideways and only leans a
  /// little up or down.
  horizontal,

  /// Across the "See all" grid: the tile follows the finger in both axes.
  free,
}

/// What a tile needs from the row or grid that hosts it to be reordered.
///
/// The host owns the preview order: [onMove] reports where the lifted tile's
/// centre is (in the host's slot coordinates) and the host decides whether
/// that is a new place. [onEnd] is the drop, the only moment anything is
/// written; [onCancel] puts the row back as it was.
@immutable
class SpaceTileReorder {
  const SpaceTileReorder({
    required this.axis,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onCancel,
    this.semanticMoves = const {},
  });

  final SpaceReorderAxis axis;
  final VoidCallback onStart;
  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  /// Screen-reader moves ("Move left", "Move up", ...) that reorder without a
  /// drag. Only the ones that can move the tile are listed.
  final Map<String, VoidCallback> semanticMoves;
}

/// [items] in the order a drag in progress shows them.
///
/// Keys in [order] keep their preview place; anything the store added while
/// the finger was down slots in at its own index, and anything it removed
/// simply drops out, so a realtime refresh never yanks the row mid-drag.
List<SpaceShortcut> spacePreviewOrder(
  List<SpaceShortcut> items,
  List<String>? order,
) {
  if (order == null) return items;
  final byKey = {for (final s in items) s.key: s};
  final out = <SpaceShortcut>[
    for (final key in order)
      if (byKey[key] case final s?) s,
  ];
  final placed = {for (final s in out) s.key};
  for (var i = 0; i < items.length; i++) {
    final s = items[i];
    if (placed.contains(s.key)) continue;
    out.insert(math.min(i, out.length), s);
  }
  return out;
}

/// The slot a lifted tile should take: the one whose centre is nearest to
/// [center], but only once it is nearer than [current]'s by more than
/// [hysteresis], so a finger resting on a boundary does not flicker the row.
int spaceNearestSlot(
  List<Offset> centers,
  Offset center,
  int current, {
  required double hysteresis,
}) {
  if (centers.isEmpty) return current;
  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < centers.length; i++) {
    final d = (centers[i] - center).distance;
    if (d < bestDistance) {
      best = i;
      bestDistance = d;
    }
  }
  if (best == current || current < 0 || current >= centers.length) {
    return best;
  }
  final currentDistance = (centers[current] - center).distance;
  return bestDistance + hysteresis < currentDistance ? best : current;
}

/// Where each tile of a "See all" grid sits: uniform tiles in rows of
/// [columns], [gap] apart sideways and [runSpacing] apart down.
@immutable
class SpaceGridGeometry {
  const SpaceGridGeometry({
    required this.width,
    required this.tileWidth,
    required this.tileHeight,
    required this.gap,
    required this.runSpacing,
  });

  /// Width the grid lays out in.
  final double width;
  final double tileWidth;
  final double tileHeight;
  final double gap;
  final double runSpacing;

  /// As many tiles as fit a row, the same count a start-aligned `Wrap`
  /// would place.
  int get columns =>
      math.max(1, ((width + gap + 0.01) / (tileWidth + gap)).floor());

  Offset slot(int index) {
    final col = index % columns;
    final row = index ~/ columns;
    return Offset(col * (tileWidth + gap), row * (tileHeight + runSpacing));
  }

  Offset center(int index) =>
      slot(index) + Offset(tileWidth / 2, tileHeight / 2);

  double height(int count) {
    if (count <= 0) return 0;
    final rows = (count + columns - 1) ~/ columns;
    return rows * tileHeight + (rows - 1) * runSpacing;
  }
}
