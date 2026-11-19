import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Where a positioned list stood: the first item on screen, and where its
/// leading edge sat as a fraction of the viewport (0 the top edge, below 0
/// partly scrolled off it).
@immutable
class ListResumePoint {
  const ListResumePoint({required this.index, required this.alignment});

  final int index;
  final double alignment;

  /// The first item on screen as [listener] last saw its list laid out.
  /// Null when nothing was laid out, or when the list sat at its top (a list
  /// built afresh starts there anyway).
  static ListResumePoint? capture(ItemPositionsListener listener) {
    ItemPosition? first;
    for (final position in listener.itemPositions.value) {
      if (position.itemTrailingEdge <= 0) continue;
      if (first == null || position.index < first.index) first = position;
    }
    if (first == null) return null;
    if (first.index == 0 && first.itemLeadingEdge >= 0) return null;
    return ListResumePoint(
      index: first.index,
      alignment: first.itemLeadingEdge.clamp(-1.0, 1.0),
    );
  }

  /// This point on a list of [itemCount] items (the last one at most).
  ListResumePoint clampedTo(int itemCount) => ListResumePoint(
    index: math.max(0, math.min(index, itemCount - 1)),
    alignment: alignment,
  );

  @override
  bool operator ==(Object other) =>
      other is ListResumePoint &&
      other.index == index &&
      other.alignment == alignment;

  @override
  int get hashCode => Object.hash(index, alignment);
}

/// A Games list across a search: where it stood as the search's hits first
/// replaced it, handed back to the list rebuilt as the search ends. Closing
/// a search (or emptying its field) lands the reader where they were, not
/// at the top.
///
/// Kept by the widget that outlives the list's swaps (the tab, which also
/// swaps the list for the empty-search state), fed on every build.
class SearchListResume {
  bool _searching = false;
  ListResumePoint? _saved;
  ListResumePoint? _restore;

  /// Where the list built now should start: the point saved as the hits
  /// came in, once they have gone, until [consumed]; null otherwise (the
  /// top). [positions] is read only on the build the hits first land in,
  /// when it still holds the list they replace.
  ListResumePoint? resolve({
    required bool searching,
    required ItemPositionsListener positions,
  }) {
    if (searching != _searching) {
      _searching = searching;
      if (searching) {
        _saved = ListResumePoint.capture(positions);
        _restore = null;
      } else {
        _restore = _saved;
        _saved = null;
      }
    }
    return searching ? null : _restore;
  }

  /// The list has been rebuilt at the restored point: lists built after it
  /// (another view mode) start where their own rules say.
  void consumed() => _restore = null;
}
