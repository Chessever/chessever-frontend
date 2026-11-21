import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Geometry of one Feed page, shared by the live clip, the puzzle page and
/// the skeleton so the board lands in exactly the same place while loading
/// and once playing, and the deck under the pages ([FeedLayout.deckTop])
/// starts where every post's board block ends.
///
/// Every page is the whole viewport, one post to a screen: nothing of the
/// next post shows under it. The post uses the whole of it, edge to edge on
/// [boardGutter], in one column as wide as the eval bar and the board
/// ([contentWidth]):
///
/// * the header: the post's one line (what it is, its event, its opening),
///   a full 44pt row at the top of the post;
/// * the board block: a player row, the board (with the eval bar or the
///   puzzle rail on its left), a player row. It never comes apart;
/// * under it, the zone, on the deck the board block flows into: the
///   evaluation chart across the whole column, the eval bar's left edge to
///   the board's right edge, and the scrub line under it; over the chart's
///   right end, the action rail ([railWidth], bare glyphs, on a frosted
///   backing that spans the zone where the chart is under them, Like at the
///   foot where the thumb rests);
/// * under the zone, at least [footGap], so on the smallest phones the rail
///   still stands clear of the dock rather than on it.
///
/// Nothing is laid over the board: ranks 1 and 2 and the h-file stay
/// playable, and its right third stays the hold-to-play-faster target.
///
/// Row heights grow with the (clamped) text scale so no label is ever cut;
/// whatever height is left goes to the board, which is also bounded by the
/// width. Height the board cannot take (it is bound by the width) is spread
/// above the post, between its board block and its zone, and under it
/// ([spread]), so each post is composed as its own frame on every screen.
///
/// In the home shell the page ends where the dock's capsule starts with the
/// dock shown (`FeedScreen` lays it out clear of the dock's whole slot), so
/// [footGap] is the least air between the post and the dock on every phone.
@immutable
class FeedLayout {
  const FeedLayout._({
    required this.width,
    required this.height,
    required this.board,
    required this.evalWidth,
    required this.rowHeight,
    required this.headerHeight,
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
      headerHeight: rows.header,
      infoHeight: rows.info,
      graphHeight: rows.zone - scrubHeight,
      railCell: (rows.zone - railInsets) / railCells,
      zoneHeight: rows.zone,
      top: topGap + split.top,
      zoneSpace: zoneGap + split.zone,
      foot: footGap + split.foot,
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
  /// of each gap's least ([topGap], [zoneGap], [footGap]).
  ///
  /// Each gap takes a fixed share, up to its own cap, so the same page reads
  /// the same on a 667pt phone and a 932pt one: above the board block, so
  /// the post does not sit hard under the bar; between the board block and
  /// the zone; and under the zone, over the [footGap] it always keeps.
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

  // The foot's share is the smallest: it already keeps [footGap], so a tall
  // phone frames its post as it did before that least was kept (about 24
  // over, 19 between and 12 + 13 under on an iPhone 15).
  static const double _topShare = 0.42;
  static const double _zoneShare = 0.34;
  static const double _footShare = 0.24;
  // The caps meet at a spare of about 90pt (a Pro Max), so every phone
  // spreads its spare by the same shares.
  static const double _topCap = 38;
  static const double _zoneCap = 30;
  static const double _footCap = 22;

  /// The page's gutter for the pages that are not posts (an ad, the tail,
  /// a message): their words keep a reading margin.
  static const double sidePadding = 16;

  /// A post's gutter either side: the board, its rows, the zone and the
  /// rail run this close to the screen's edges, so the board is as large as
  /// the screen allows.
  static const double boardGutter = 8;

  /// The action rail: one column of bare glyphs (on a frosted backing over a
  /// chart), laid over the zone's right end (the marks are the buttons, as
  /// in the bottom bar). As wide as a full target.
  static const double railWidth = 44;

  /// Between the rail and what the zone keeps clear of it: the chart's move
  /// line, its curve, the scrub line.
  static const double railGap = 8;

  /// A rail cell's least height: a full target around its glyph (and the
  /// like count under the heart). The rail spans the zone, so its cells
  /// grow with it ([railCell]) and never shrink below this.
  static const double railCellMin = 44;

  /// Cells the rail keeps room for: Analyze, Share, Save, Like (a puzzle's
  /// Hint, Retry, Solution, Next).
  static const int railCells = 4;

  /// The backing's air above its first cell and under its last. None over
  /// the first: its glyph already sits a cell's padding (10pt) inside the
  /// round top end. Under the last, enough that the like count under the
  /// heart sits where the round bottom end is still wide enough for the
  /// widest count ([railCountRoom]), clear of its rim.
  static const double railInsetTop = 0;
  static const double railInsetBottom = 8;
  static const double railInsets = railInsetTop + railInsetBottom;

  /// A rail cell's glyph: the bottom bar's mark size, not a thumb-filling
  /// one; the cell around it is the target.
  static const double railGlyph = 24;

  /// Between the heart and its like count.
  static const double railGlyphGap = 2;

  /// The widest the like count is ever set: what the backing's round bottom
  /// end leaves at the count's baseline, less 3pt of air either side, so a
  /// count never touches the rim (`feedRailCountFontSize` fits the widest
  /// compact count, "88.8K", to it at every text size).
  static const double railCountRoom = 33;

  /// Type size of the player rows above and below the board. They span
  /// the board's full width, so they carry a reading size rather than a
  /// game card's compact one; [_Rows.row] gives them the height for it.
  static const double playerFontSize = 12;

  /// The eval bar / puzzle rail width on the 393pt design frame; callers
  /// pass the scaled game-card width (`20.w`).
  static const double defaultEvalWidth = 20;

  /// The least space above the post ([top] adds the page's spare). None:
  /// the header's 44pt row carries its own air above its line.
  static const double topGap = 0;

  /// Between the player rows and the board: fixed, they are one block.
  static const double gap = 4;

  /// The least space between the board block and the zone.
  static const double zoneGap = 6;

  /// The least space under the zone: in the home shell, between the rail's
  /// foot and the dock's capsule as it stands when shown, so the frosted
  /// backing never sits on the dock however short the phone (360x640 with
  /// three-button navigation, an iPhone SE). The dock's own least gap to the
  /// screen's edge, so the two floating objects keep one rhythm.
  static const double footGap = 12;

  /// The scrub line's row: a full 44pt touch target across the column.
  static const double scrubHeight = 44;

  /// The scrub track's line inside its row: a little above the row's middle,
  /// so the line sits with the chart it drives.
  static const double scrubTrackCenter = 18;

  /// The scrub track's thickness at rest (it thickens under the finger).
  static const double scrubTrack = 6;
  static const double minBoard = 160;

  /// The evaluation chart's plot, under its move line, at its least; a
  /// zone taller than the chart needs (the rail's four full cells) gives the
  /// plot the rest ([graphHeight]).
  static const double chartPlotHeight = 75;

  /// The chart's move line: its 18/24 label's line at [scaler]'s size,
  /// never less than 24pt (a fixed 24pt box shaved the label's descenders
  /// at large text, so "Ng5" read "Na5").
  static double moveInfoHeightFor(TextScaler scaler) =>
      math.max(24.0, scaler.scale(18) * 24 / 18).ceilToDouble();

  /// The evaluation chart's whole slot at its least: its move line, the
  /// plot, and the air either side of the plot.
  static double graphHeightFor(TextScaler scaler) =>
      moveInfoHeightFor(scaler) + chartAir + chartPlotHeight;

  /// The air above the plot (under the move line) and under it.
  static const double chartAirAbove = 10;
  static const double chartAirBelow = 9;
  static const double chartAir = chartAirAbove + chartAirBelow;

  /// A variation's move line keeps its 44pt controls and enough room for
  /// the same 15/20 text line at the viewer's reading size.
  static double moveStripHeightFor(TextScaler scaler) =>
      math.max(44.0, math.max(20.0, scaler.scale(15) * 20 / 15) + 12);

  static double _line(TextScaler scaler, double fontSize, double lineHeight) =>
      math.max(lineHeight, scaler.scale(fontSize) * lineHeight / fontSize);

  final double width;
  final double height;
  final double board;

  /// The column left of the board: the eval bar or the puzzle rail.
  final double evalWidth;

  /// A player row's height.
  final double rowHeight;

  /// The header's line at the top of the post (what it is, its event, its
  /// opening), a full 44pt target at its least.
  final double headerHeight;

  /// A puzzle's status row, in the middle of its zone.
  final double infoHeight;

  /// The evaluation chart's slot: the zone over the scrub line. At least
  /// [graphHeightFor]; the plot takes what the rail's cells add.
  final double graphHeight;

  /// One cell of the action rail: the zone's height, less the backing's
  /// [railInsets], over [railCells]; at least [railCellMin].
  final double railCell;

  /// The zone under the board block: the chart and the scrub line, with
  /// the rail over their right end, as tall as the taller of the two.
  final double zoneHeight;

  /// Space above the post.
  final double top;

  /// Space between the board block and the zone.
  final double zoneSpace;

  /// Space under the zone: at least [footGap].
  final double foot;

  /// Eval bar + board; the header, the player rows and the chart share this
  /// width.
  double get contentWidth => evalWidth + board;

  /// Left edge of the post's column (centred when the board is
  /// height-bound): the eval bar's, the header's and the chart's.
  double get contentLeft => math.max(boardGutter, (width - contentWidth) / 2);

  /// Right edge of the post's column: the board's, the chart's and the
  /// rail's.
  double get contentRight => contentLeft + contentWidth;

  /// Top of the header line.
  double get headerTop => top;

  /// Top of the black player row, under the header.
  double get blackRowTop => headerTop + headerHeight;

  /// Top of the board inside the page.
  double get boardTop => blackRowTop + rowHeight + gap;

  double get boardBottom => boardTop + board;

  /// Top of the white player row.
  double get whiteRowTop => boardBottom + gap;

  /// Where the board block ends: the foot of the white player row. The deck
  /// under the pages starts here, so the board flows into the chart.
  double get deckTop => whiteRowTop + rowHeight;

  /// Top of the zone.
  double get zoneTop => deckTop + zoneSpace;

  double get zoneBottom => zoneTop + zoneHeight;

  /// Top of the rail's last cell (Like, a puzzle's Next): over the
  /// backing's [railInsetBottom].
  double get railLastCellTop => zoneBottom - railInsetBottom - railCell;

  /// The middle of the rail's cells, between the backing's insets: what a
  /// puzzle's status beside the rail is centred on, so it sits level with
  /// the marks rather than with the zone.
  double get railCellsMiddle =>
      zoneTop + railInsetTop + railCell * railCells / 2;

  /// The rail, over the chart's right end: on the column's right edge (so on
  /// a tablet it stays with the post), from the zone's top to its foot.
  double get railLeft => contentRight - railWidth;
  double get railHeight => zoneHeight;
  double get railTop => zoneTop;

  /// What the chart's live parts (its move line, its curve and cursor) and
  /// the scrub line keep clear of at the column's right end: the rail and
  /// its gap. Only the chart's ground runs on under the rail.
  double get railReserve => railWidth + railGap;

  /// The zone's room beside the rail: from the post's left edge to the
  /// rail's gap. The scrub line and a puzzle's status end here.
  double get leftColumnWidth => math.max(0, railLeft - railGap - contentLeft);

  /// The left column's right edge.
  double get leftColumnRight => contentLeft + leftColumnWidth;

  /// Top of the chart, at the zone's top.
  double get graphTop => zoneTop;

  /// Top of the scrub line's row, under the chart, at the zone's foot.
  double get scrubTop => graphTop + graphHeight;
}

/// Row heights at one text size.
class _Rows {
  const _Rows({
    required this.header,
    required this.row,
    required this.info,
    required this.graph,
  });

  factory _Rows.of(TextScaler scaler) {
    return _Rows(
      // One header line in a full 44pt target, so every tappable segment
      // in it (the event, the opening) is a real target.
      header: math.max(44.0, FeedLayout._line(scaler, 13, 18) + 12),
      // The player rows: [FeedLayout.playerFontSize] type at 1.2 height,
      // grown with scale, plus room for the clock's frame.
      row: math.max(24.0, scaler.scale(FeedLayout.playerFontSize) * 1.2 + 6),
      // A puzzle's status: the move strip's 44pt line.
      info: FeedLayout.moveStripHeightFor(scaler),
      graph: FeedLayout.graphHeightFor(scaler),
    );
  }

  final double header;
  final double row;
  final double info;
  final double graph;

  /// The zone: the chart and the scrub line under it, or the rail's four
  /// full cells on their backing over their right end, whichever is taller.
  double get zone => math.max(
    graph + FeedLayout.scrubHeight,
    FeedLayout.railCells * FeedLayout.railCellMin + FeedLayout.railInsets,
  );

  /// Every row of a post except the board, each gap at its least.
  double get fixed =>
      FeedLayout.topGap +
      header +
      row +
      FeedLayout.gap +
      FeedLayout.gap +
      row +
      FeedLayout.zoneGap +
      zone +
      FeedLayout.footGap;
}
