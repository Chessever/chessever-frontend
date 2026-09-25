import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Geometry of one Feed page, shared by the live clip, the puzzle page and
/// the skeleton so the board lands in exactly the same place while loading
/// and once playing.
///
/// Top to bottom: the one-line post header, a player row, the board (with
/// the eval bar or the puzzle rail on its left), a player row, the move
/// strip, the action row, then whatever height is spare, then the scrub
/// line. Spare height always collects above the scrub line, never between
/// the header and the board, so every post type starts at the same place.
///
/// Row heights grow with the (clamped) text scale so no label is ever cut;
/// whatever height is left goes to the board, which is also bounded by the
/// width.
@immutable
class FeedLayout {
  const FeedLayout._({
    required this.width,
    required this.height,
    required this.board,
    required this.evalWidth,
    required this.metaHeight,
    required this.rowHeight,
    required this.infoHeight,
    required this.actionsHeight,
  });

  /// [evalWidth] is the column left of the board: the eval bar (0 when the
  /// viewer's engine settings hide it) or the puzzle rail.
  factory FeedLayout.resolve(
    BoxConstraints constraints,
    TextScaler scaler, {
    double evalWidth = defaultEvalWidth,
  }) {
    double line(double fontSize, double lineHeight) =>
        math.max(lineHeight, scaler.scale(fontSize) * lineHeight / fontSize);

    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    // One header line in a full 44pt target, so every tappable segment in it
    // (the event, the opening) is a real target.
    final meta = math.max(44.0, line(13, 18) + 12);
    // The game cards' player row: 10pt type in a 20pt row, grown with scale.
    final row = math.max(20.0, scaler.scale(10) * 1.15 + 6);
    // The move strip: 44pt transport controls, moves at 15/20.
    final info = math.max(44.0, line(15, 20) + 12);
    final actions = math.max(56.0, 22 + 5 + line(12, 14) + 12);

    final fixed =
        topGap +
        meta +
        gap +
        row +
        gap +
        gap +
        row +
        infoGap +
        info +
        actionsGap +
        actions +
        minSpacer +
        scrubHeight;
    final byWidth = width - 2 * sidePadding - evalWidth;
    final byHeight = height - fixed;
    final board = math.max(minBoard, math.min(byWidth, byHeight));
    assert(fixed == _fixedHeight(scaler));

    return FeedLayout._(
      width: width,
      height: height,
      board: board.floorToDouble(),
      evalWidth: evalWidth,
      metaHeight: meta,
      rowHeight: row,
      infoHeight: info,
      actionsHeight: actions,
    );
  }

  /// The height one post needs on a page [width] wide when its board is as
  /// wide as the page allows: everything [FeedLayout.resolve] stacks, with no
  /// spare. Feed sizes its pages to this, so a tall screen shows the next
  /// post under the current one instead of an empty band under the actions.
  static double naturalHeight(
    double width,
    TextScaler scaler, {
    double evalWidth = defaultEvalWidth,
  }) {
    final board = math.max(minBoard, width - 2 * sidePadding - evalWidth);
    return _fixedHeight(scaler) + board.floorToDouble();
  }

  /// How Feed stands its pages on a viewport [viewport] tall: every page
  /// [extent] tall, that is one post ([naturalHeight], kept between half
  /// and all of the viewport) and a blank [foot] under it.
  ///
  /// On a screen taller than a post the top of the next page shows under
  /// the current one: the peek. The foot makes the peek end in a gap
  /// between the next post's rows, never through one: not across its
  /// header line or a player row, and not a few points into its board,
  /// which leaves a sliced strip of squares along the screen's bottom edge.
  /// Where it would, the page grows by exactly the points it takes for the
  /// peek to stop just above that row. A board may show a slice when it is
  /// a real one, at least half a square. The foot sits under the scrub
  /// line, so the line stays with its own post rather than drifting down
  /// towards the next one.
  static ({double extent, double foot}) pageFit(
    double width,
    double viewport,
    TextScaler scaler, {
    double evalWidth = defaultEvalWidth,
  }) {
    final post = naturalHeight(width, scaler, evalWidth: evalWidth);
    if (!viewport.isFinite || viewport <= 0) return (extent: post, foot: 0.0);
    final extent = post.clamp(viewport * 0.5, viewport).toDouble();
    final peek = viewport - extent;
    if (peek <= 0) return (extent: extent, foot: 0.0);
    final next = FeedLayout.resolve(
      BoxConstraints(maxWidth: width, maxHeight: extent),
      scaler,
      evalWidth: evalWidth,
    );
    final clean = next._cleanPeek(peek, scaler);
    return (extent: viewport - clean, foot: peek - clean);
  }

  /// How far above a row the peek stops when it would have cut into it:
  /// inside the gap between that row and the one before it.
  static const double peekClearance = 2;

  /// [peek] as it may end over this post's top: moved up to just above a
  /// row it would cut, unchanged where it ends in a gap or well into the
  /// board.
  double _cleanPeek(double peek, TextScaler scaler) {
    double line(double fontSize, double lineHeight) =>
        math.max(lineHeight, scaler.scale(fontSize) * lineHeight / fontSize);
    // What each row draws: the header's line (its tappable segments are
    // 20pt tall), the player rows' names and flags inside their 3pt
    // padding, and the board.
    final headInk = math.max(20.0, line(13, 18));
    final headTop = topGap + (metaHeight - headInk) / 2;
    final rowInk = rowHeight - 6;
    final rowOver = topGap + metaHeight + gap + 3;
    final rowUnder = boardBottom + gap + 3;
    final bands = <(double, double, double)>[
      (headTop, headTop + headInk, headInk),
      (rowOver, rowOver + rowInk, rowInk),
      // Half a square is a board seen; less is a sliver.
      (boardTop, boardBottom, math.max(16.0, board / 16)),
      (rowUnder, rowUnder + rowInk, rowInk),
    ];
    for (final (top, bottom, least) in bands) {
      if (peek > top && peek < bottom && peek - top < least) {
        return math.max(0.0, top - peekClearance);
      }
    }
    return peek;
  }

  /// Every row of a post except the board, at [scaler]'s text size.
  static double _fixedHeight(TextScaler scaler) {
    double line(double fontSize, double lineHeight) =>
        math.max(lineHeight, scaler.scale(fontSize) * lineHeight / fontSize);
    final meta = math.max(44.0, line(13, 18) + 12);
    final row = math.max(20.0, scaler.scale(10) * 1.15 + 6);
    final info = math.max(44.0, line(15, 20) + 12);
    final actions = math.max(56.0, 22 + 5 + line(12, 14) + 12);
    return topGap +
        meta +
        gap +
        row +
        gap +
        gap +
        row +
        infoGap +
        info +
        actionsGap +
        actions +
        minSpacer +
        scrubHeight;
  }

  static const double sidePadding = 16;

  /// The eval bar / puzzle rail width on the 393pt design frame; callers
  /// pass the scaled game-card width (`20.w`).
  static const double defaultEvalWidth = 20;
  static const double topGap = 2;
  static const double gap = 4;
  static const double infoGap = 10;
  static const double actionsGap = 8;
  static const double minSpacer = 8;

  /// The scrub line's row: a full 44pt touch target across the page.
  static const double scrubHeight = 44;

  /// The scrub track's line inside its row: a little above the row's middle,
  /// so the line sits with its own post's actions rather than halfway to the
  /// next post's header.
  static const double scrubTrackCenter = 18;

  /// The scrub track's thickness at rest (it thickens under the finger).
  static const double scrubTrack = 6;
  static const double minBoard = 160;

  final double width;
  final double height;
  final double board;

  /// The column left of the board; 0 when the eval bar is hidden.
  final double evalWidth;
  final double metaHeight;
  final double rowHeight;
  final double infoHeight;
  final double actionsHeight;

  /// Eval bar + board; the player rows share this width.
  double get contentWidth => evalWidth + board;

  /// Left edge of the content column (centred when the board is height-bound).
  double get contentLeft => math.max(sidePadding, (width - contentWidth) / 2);

  /// Width of the text rows (post header, move strip, action row), which
  /// start at [sidePadding]: a height-bound board narrows only itself and
  /// its player rows, never the words around it.
  double get rowWidth => math.max(0, width - 2 * sidePadding);

  /// Top of the board inside the page.
  double get boardTop => topGap + metaHeight + gap + rowHeight + gap;

  double get boardBottom => boardTop + board;

  /// Bottom of the action row; the spare height starts here.
  double get actionsBottom =>
      boardBottom +
      gap +
      rowHeight +
      infoGap +
      infoHeight +
      actionsGap +
      actionsHeight;
}
