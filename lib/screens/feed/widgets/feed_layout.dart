import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Geometry of one Feed page, shared by the live clip, the puzzle page and
/// the skeleton so the board lands in exactly the same place while loading
/// and once playing.
///
/// Every page is the whole viewport, one post to a screen: nothing of the
/// next post shows under it. Top to bottom: the one-line post header, a
/// player row, the board (with the eval bar or the puzzle rail on its
/// left), a player row, the move strip, the action row and the scrub line.
///
/// The header, the player rows and the board are one block and never come
/// apart. Row heights grow with the (clamped) text scale so no label is ever
/// cut; whatever height is left goes to the board, which is also bounded by
/// the width. On a phone the width binds first, so a page is usually taller
/// than its post needs: that spare height is spread through the page
/// ([spread]) rather than left in one empty band, so each post is composed
/// as its own frame on every screen size. A puzzle has no scrub line; it
/// spreads that line's room too ([scrublessTop] and its siblings).
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
    required this.top,
    required this.infoSpace,
    required this.actionsSpace,
    required this.scrubSpace,
    required this.foot,
  });

  /// [evalWidth] is the column left of the board: the eval bar (0 when the
  /// viewer's engine settings hide it) or the puzzle rail.
  factory FeedLayout.resolve(
    BoxConstraints constraints,
    TextScaler scaler, {
    double evalWidth = defaultEvalWidth,
  }) {
    final rows = _Rows.of(scaler);
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final fixed = rows.fixed;
    final byWidth = width - 2 * sidePadding - evalWidth;
    final byHeight = height - fixed;
    final board = math
        .max(minBoard, math.min(byWidth, byHeight))
        .floorToDouble();
    final spare = height.isFinite ? math.max(0.0, height - fixed - board) : 0.0;
    final split = spread(spare);

    return FeedLayout._(
      width: width,
      height: height,
      board: board,
      evalWidth: evalWidth,
      metaHeight: rows.meta,
      rowHeight: rows.row,
      infoHeight: rows.info,
      actionsHeight: rows.actions,
      top: topGap + split.top,
      infoSpace: infoGap + split.info,
      actionsSpace: actionsGap + split.actions,
      scrubSpace: minSpacer + split.scrub,
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
    final board = math.max(minBoard, width - 2 * sidePadding - evalWidth);
    return _Rows.of(scaler).fixed + board.floorToDouble();
  }

  /// How [spare] points of page height are spread through a post, on top
  /// of each gap's least ([topGap], [infoGap], [actionsGap], [minSpacer]).
  ///
  /// Each gap takes a fixed share, up to its own cap, so the same page reads
  /// the same on a 667pt phone and a 932pt one:
  /// * above the header, so the post does not sit hard under the bar and
  ///   the board comes down towards the optical centre of the page;
  /// * between the board's block and the move strip;
  /// * a little between the move strip and the actions, which belong
  ///   together;
  /// * above the scrub line, which becomes the page's foot.
  ///
  /// Nothing goes between the header and the board: they are one block.
  /// Height beyond every cap (a tall tablet) is split evenly above the
  /// header and under the scrub line, so the post stands centred.
  static ({double top, double info, double actions, double scrub, double foot})
  spread(double spare) {
    if (!spare.isFinite || spare <= 0) {
      return (top: 0, info: 0, actions: 0, scrub: 0, foot: 0);
    }
    final top = math.min(spare * _topShare, _topCap);
    final info = math.min(spare * _infoShare, _infoCap);
    final actions = math.min(spare * _actionsShare, _actionsCap);
    final scrub = math.min(spare * _scrubShare, _scrubCap);
    // Rounding dust is not height: below a micro-point nothing is over.
    final over = spare - top - info - actions - scrub;
    final rest = over > 1e-6 ? over : 0.0;
    return (
      top: top + rest / 2,
      info: info,
      actions: actions,
      scrub: scrub,
      foot: rest / 2,
    );
  }

  static const double _topShare = 0.30;
  static const double _infoShare = 0.25;
  static const double _actionsShare = 0.15;
  static const double _scrubShare = 0.30;
  // The caps meet at a spare of 120pt (a Pro Max), so every phone spreads
  // its spare by the same shares.
  static const double _topCap = 36;
  static const double _infoCap = 30;
  static const double _actionsCap = 18;
  static const double _scrubCap = 36;

  static const double sidePadding = 16;

  /// The eval bar / puzzle rail width on the 393pt design frame; callers
  /// pass the scaled game-card width (`20.w`).
  static const double defaultEvalWidth = 20;

  /// The least space above the header ([top] adds the page's spare).
  static const double topGap = 2;

  /// Between the header, the player rows and the board: fixed, they are one
  /// block.
  static const double gap = 4;

  /// The least space between the board's block and the move strip.
  static const double infoGap = 10;

  /// The least space between the move strip and the actions.
  static const double actionsGap = 8;

  /// The least space between the actions and the scrub line.
  static const double minSpacer = 8;

  /// The scrub line's row: a full 44pt touch target across the page.
  static const double scrubHeight = 44;

  /// The scrub track's line inside its row: a little above the row's middle,
  /// so the line sits with its own post's actions.
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

  /// Space above the header.
  final double top;

  /// Space between the lower player row and the move strip.
  final double infoSpace;

  /// Space between the move strip and the action row.
  final double actionsSpace;

  /// Space between the action row and the scrub line.
  final double scrubSpace;

  /// Space under the scrub line: only where the page is taller than every
  /// gap's cap allows for.
  final double foot;

  /// Eval bar + board; the player rows share this width.
  double get contentWidth => evalWidth + board;

  /// Left edge of the content column (centred when the board is height-bound).
  double get contentLeft => math.max(sidePadding, (width - contentWidth) / 2);

  /// Width of the text rows (post header, move strip, action row), which
  /// start at [sidePadding]: a height-bound board narrows only itself and
  /// its player rows, never the words around it.
  double get rowWidth => math.max(0, width - 2 * sidePadding);

  /// Top of the board inside the page.
  double get boardTop => top + metaHeight + gap + rowHeight + gap;

  double get boardBottom => boardTop + board;

  /// Top of the move strip.
  double get infoTop => boardBottom + gap + rowHeight + infoSpace;

  /// Bottom of the action row.
  double get actionsBottom =>
      infoTop + infoHeight + actionsSpace + actionsHeight;

  /// Top of the scrub line's row.
  double get scrubTop => actionsBottom + scrubSpace;

  // ---------------------------------------------------------- no scrub line

  /// How far into the scrub line's row a game page's ink reaches (the
  /// track, its thumb and the counter), plus the space an action row keeps
  /// under its words: the actions of a page with no scrub line end here, so
  /// they end where a game page does.
  static const double _scrubReach = 37;

  /// A page with no scrub line (a puzzle) has that line's room over. It is
  /// not left as a band under the actions: it is spread like the page's
  /// spare, so the post stands centred in its frame and ends where a game
  /// post ends.
  double get _scrublessRoom => scrubSpace + _scrubReach;

  /// [top] on a page with no scrub line: part of the line's room, so the
  /// post stands lower, towards the middle of its frame.
  double get scrublessTop => top + _scrublessRoom * 0.4;

  /// [infoSpace] on a page with no scrub line.
  double get scrublessInfoSpace => infoSpace + _scrublessRoom * 0.2;

  /// [actionsSpace] on a page with no scrub line: the actions come down to
  /// where a game page's scrub line ends.
  double get scrublessActionsSpace => actionsSpace + _scrublessRoom * 0.4;

  /// Space under the actions on a page with no scrub line.
  double get scrublessFoot => scrubHeight - _scrubReach + foot;
}

/// Row heights at one text size.
class _Rows {
  const _Rows(this.meta, this.row, this.info, this.actions);

  factory _Rows.of(TextScaler scaler) {
    double line(double fontSize, double lineHeight) =>
        math.max(lineHeight, scaler.scale(fontSize) * lineHeight / fontSize);
    return _Rows(
      // One header line in a full 44pt target, so every tappable segment in
      // it (the event, the opening) is a real target.
      math.max(44.0, line(13, 18) + 12),
      // The game cards' player row: 10pt type in a 20pt row, grown with
      // scale.
      math.max(20.0, scaler.scale(10) * 1.15 + 6),
      // The move strip: 44pt transport controls, moves at 15/20.
      math.max(44.0, line(15, 20) + 12),
      math.max(56.0, 22 + 5 + line(12, 14) + 12),
    );
  }

  final double meta;
  final double row;
  final double info;
  final double actions;

  /// Every row of a post except the board, each gap at its least.
  double get fixed =>
      FeedLayout.topGap +
      meta +
      FeedLayout.gap +
      row +
      FeedLayout.gap +
      FeedLayout.gap +
      row +
      FeedLayout.infoGap +
      info +
      FeedLayout.actionsGap +
      actions +
      FeedLayout.minSpacer +
      FeedLayout.scrubHeight;
}
