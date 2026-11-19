import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Geometry of one Feed page, shared by the live clip, the puzzle page and
/// the skeleton so the board lands in exactly the same place while loading
/// and once playing, and the deck under the pages ([FeedLayout.deckTop])
/// starts where every post's board block ends.
///
/// Every page is the whole viewport, one post to a screen: nothing of the
/// next post shows under it. The post uses the whole of it, edge to edge on
/// [boardGutter]:
///
/// * the board block: a player row, the board (with the eval bar or the
///   puzzle rail on its left), a player row. It never comes apart;
/// * under it, the zone: on the left the evaluation chart, the scrub line
///   and the caption (the post's one line of what it is); on the right the
///   action rail ([railWidth], its cells glyph over word, Like at the foot
///   where the thumb rests).
///
/// Nothing is laid over the board: ranks 1 and 2 and the h-file stay
/// playable, and its right third stays the hold-to-play-faster target.
///
/// Row heights grow with the (clamped) text scale so no label is ever cut;
/// whatever height is left goes to the board, which is also bounded by the
/// width. Height the board cannot take (it is bound by the width) is spread
/// above the post, between its board block and its zone, and under it
/// ([spread]), so each post is composed as its own frame on every screen.
@immutable
class FeedLayout {
  const FeedLayout._({
    required this.width,
    required this.height,
    required this.board,
    required this.evalWidth,
    required this.rowHeight,
    required this.captionHeight,
    required this.infoHeight,
    required this.graphHeight,
    required this.railCell,
    required this.zoneHeight,
    required this.top,
    required this.zoneSpace,
    required this.foot,
  });

  /// [evalWidth] is the column left of the board: the eval bar or the
  /// puzzle rail.
  factory FeedLayout.resolve(
    BoxConstraints constraints,
    TextScaler scaler, {
    double evalWidth = defaultEvalWidth,
  }) {
    final rows = _Rows.of(scaler);
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final fixed = rows.fixed;
    final byWidth = width - 2 * boardGutter - evalWidth;
    final byHeight = height - fixed;
    // A micro-point of tolerance before flooring: a page given exactly
    // [naturalHeight] leaves floating dust (324.99999) that must not cost
    // the board a whole point.
    final board = (math.max(minBoard, math.min(byWidth, byHeight)) + 1e-6)
        .floorToDouble();
    final spare = height.isFinite ? math.max(0.0, height - fixed - board) : 0.0;
    final split = spread(spare);

    return FeedLayout._(
      width: width,
      height: height,
      board: board,
      evalWidth: evalWidth,
      rowHeight: rows.row,
      captionHeight: rows.caption,
      infoHeight: rows.info,
      graphHeight: rows.graph,
      railCell: rows.railCell,
      zoneHeight: rows.zone,
      top: topGap + split.top,
      zoneSpace: zoneGap + split.zone,
      foot: split.foot,
    );
  }

  /// The height one post needs on a page [width] wide when its board is as
  /// wide as the page allows: every row at its least, no spare.
  static double naturalHeight(
    double width,
    TextScaler scaler, {
    double evalWidth = defaultEvalWidth,
  }) {
    final board = math.max(minBoard, width - 2 * boardGutter - evalWidth);
    return _Rows.of(scaler).fixed + board.floorToDouble();
  }

  /// How [spare] points of page height are spread through a post, on top
  /// of each gap's least ([topGap], [zoneGap]).
  ///
  /// Each gap takes a fixed share, up to its own cap, so the same page reads
  /// the same on a 667pt phone and a 932pt one: above the board block, so
  /// the post does not sit hard under the bar; between the board block and
  /// the zone; and under the zone, so it does not sit hard on the dock.
  /// Height beyond every cap (a tall tablet) is split evenly above and
  /// under the post, so it stands centred.
  static ({double top, double zone, double foot}) spread(double spare) {
    if (!spare.isFinite || spare <= 0) {
      return (top: 0, zone: 0, foot: 0);
    }
    final top = math.min(spare * _topShare, _topCap);
    final zone = math.min(spare * _zoneShare, _zoneCap);
    final foot = math.min(spare * _footShare, _footCap);
    // Rounding dust is not height: below a micro-point nothing is over.
    final over = spare - top - zone - foot;
    final rest = over > 1e-6 ? over : 0.0;
    return (top: top + rest / 2, zone: zone, foot: foot + rest / 2);
  }

  static const double _topShare = 0.35;
  static const double _zoneShare = 0.30;
  static const double _footShare = 0.35;
  // The caps meet at a spare of about 100pt (a Pro Max), so every phone
  // spreads its spare by the same shares.
  static const double _topCap = 36;
  static const double _zoneCap = 30;
  static const double _footCap = 36;

  /// The page's gutter for the pages that are not posts (an ad, the tail,
  /// a message): their words keep a reading margin.
  static const double sidePadding = 16;

  /// A post's gutter either side: the board, its rows, the zone and the
  /// rail run this close to the screen's edges, so the board is as large as
  /// the screen allows.
  static const double boardGutter = 8;

  /// The action rail: one column of bare glyphs, no words (the marks are
  /// the buttons, as in the bottom bar).
  static const double railWidth = 56;

  /// Between the zone's left column and the rail.
  static const double railGap = 8;

  /// A rail cell's height: a full target around its glyph (and the like
  /// count under the heart).
  static const double railCellMin = 50;

  /// Cells the rail keeps room for: Analyze, Share, Save, Like (a puzzle's
  /// Hint, Retry, Solution, Next).
  static const int railCells = 4;

  /// A rail cell's glyph: bulky, a thumb-sized mark.
  static const double railGlyph = 30;

  /// Between the heart and its like count.
  static const double railGlyphGap = 2;

  /// Type size of the player rows above and below the board. They span
  /// the board's full width, so they carry a reading size rather than a
  /// game card's compact one; [_Rows.row] gives them the height for it.
  static const double playerFontSize = 12;

  /// The eval bar / puzzle rail width on the 393pt design frame; callers
  /// pass the scaled game-card width (`20.w`).
  static const double defaultEvalWidth = 20;

  /// The least space above the board block ([top] adds the page's spare).
  static const double topGap = 4;

  /// Between the player rows and the board: fixed, they are one block.
  static const double gap = 4;

  /// The least space between the board block and the zone.
  static const double zoneGap = 6;

  /// The scrub line's row: a full 44pt touch target across the column.
  static const double scrubHeight = 44;

  /// The scrub track's line inside its row: a little above the row's middle,
  /// so the line sits with the chart it drives.
  static const double scrubTrackCenter = 18;

  /// The scrub track's thickness at rest (it thickens under the finger).
  static const double scrubTrack = 6;
  static const double minBoard = 160;

  /// The evaluation chart's plot, under its move line.
  static const double chartPlotHeight = 75;

  /// The chart's move line: its 18/24 label's line at [scaler]'s size,
  /// never less than 24pt (a fixed 24pt box shaved the label's descenders
  /// at large text, so "Ng5" read "Na5").
  static double moveInfoHeightFor(TextScaler scaler) =>
      math.max(24.0, scaler.scale(18) * 24 / 18).ceilToDouble();

  /// The evaluation chart's whole slot: its move line, the plot, and the
  /// air either side of the plot.
  static double graphHeightFor(TextScaler scaler) =>
      moveInfoHeightFor(scaler) + 10 + chartPlotHeight + 9;

  /// A variation's move line keeps its 44pt controls and enough room for
  /// the same 15/20 text line at the viewer's reading size.
  static double moveStripHeightFor(TextScaler scaler) =>
      math.max(44.0, math.max(20.0, scaler.scale(15) * 20 / 15) + 12);

  /// A rail cell: the glyph is the whole button, so its height no longer
  /// follows the text size; the like count under the heart is capped to
  /// fit it.
  static double railCellFor(TextScaler scaler) => railCellMin;

  static double _line(TextScaler scaler, double fontSize, double lineHeight) =>
      math.max(lineHeight, scaler.scale(fontSize) * lineHeight / fontSize);

  final double width;
  final double height;
  final double board;

  /// The column left of the board: the eval bar or the puzzle rail.
  final double evalWidth;

  /// A player row's height.
  final double rowHeight;

  /// The caption's line (the post's one line: what it is, its event, its
  /// opening), a full 44pt target at its least.
  final double captionHeight;

  /// A puzzle's status row, at the top of its zone.
  final double infoHeight;

  /// The evaluation chart's slot ([graphHeightFor]).
  final double graphHeight;

  /// One cell of the action rail ([railCellFor]).
  final double railCell;

  /// The zone under the board block: the taller of its left column (chart,
  /// scrub line, caption) and the rail.
  final double zoneHeight;

  /// Space above the board block.
  final double top;

  /// Space between the board block and the zone.
  final double zoneSpace;

  /// Space under the zone.
  final double foot;

  /// Eval bar + board; the player rows share this width, and the zone
  /// spans it.
  double get contentWidth => evalWidth + board;

  /// Left edge of the post's column (centred when the board is
  /// height-bound).
  double get contentLeft => math.max(boardGutter, (width - contentWidth) / 2);

  /// Right edge of the post's column: the board's, and the rail's.
  double get contentRight => contentLeft + contentWidth;

  /// Top of the black player row.
  double get blackRowTop => top;

  /// Top of the board inside the page.
  double get boardTop => top + rowHeight + gap;

  double get boardBottom => boardTop + board;

  /// Top of the white player row.
  double get whiteRowTop => boardBottom + gap;

  /// Where the board block ends: the foot of the white player row. The deck
  /// under the pages starts here, so the board flows into the chart.
  double get deckTop => whiteRowTop + rowHeight;

  /// Top of the zone.
  double get zoneTop => deckTop + zoneSpace;

  double get zoneBottom => zoneTop + zoneHeight;

  /// The rail, anchored to the board column's right edge (so on a tablet it
  /// stays with the post), and to the zone's foot.
  double get railLeft => contentRight - railWidth;
  double get railHeight => railCells * railCell;
  double get railTop => zoneBottom - railHeight;

  /// The zone's left column: from the post's left edge to the rail.
  double get leftColumnWidth => math.max(0, railLeft - railGap - contentLeft);

  /// The left column's right edge.
  double get leftColumnRight => contentLeft + leftColumnWidth;

  /// Top of the chart, at the zone's top.
  double get graphTop => zoneTop;

  /// Top of the scrub line's row, under the chart.
  double get scrubTop => graphTop + graphHeight;

  /// Top of the caption, at the zone's foot.
  double get captionTop => zoneBottom - captionHeight;
}

/// Row heights at one text size.
class _Rows {
  const _Rows({
    required this.caption,
    required this.row,
    required this.info,
    required this.graph,
    required this.railCell,
  });

  factory _Rows.of(TextScaler scaler) {
    return _Rows(
      // One caption line in a full 44pt target, so every tappable segment
      // in it (the event, the opening) is a real target.
      caption: math.max(44.0, FeedLayout._line(scaler, 13, 18) + 12),
      // The player rows: [FeedLayout.playerFontSize] type at 1.2 height,
      // grown with scale, plus room for the clock's frame.
      row: math.max(24.0, scaler.scale(FeedLayout.playerFontSize) * 1.2 + 6),
      // A puzzle's status: the move strip's 44pt line.
      info: FeedLayout.moveStripHeightFor(scaler),
      graph: FeedLayout.graphHeightFor(scaler),
      railCell: FeedLayout.railCellFor(scaler),
    );
  }

  final double caption;
  final double row;
  final double info;
  final double graph;
  final double railCell;

  /// The zone: the chart, the scrub line and the caption on the left, the
  /// rail on the right, whichever is taller.
  double get zone => math.max(
    graph + FeedLayout.scrubHeight + caption,
    FeedLayout.railCells * railCell,
  );

  /// Every row of a post except the board, each gap at its least.
  double get fixed =>
      FeedLayout.topGap +
      row +
      FeedLayout.gap +
      FeedLayout.gap +
      row +
      FeedLayout.zoneGap +
      zone;
}
