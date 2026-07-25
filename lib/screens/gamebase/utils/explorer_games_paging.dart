import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// Deterministic paging for the opening explorer's inline games strip.
///
/// The strip is drawn inside the ordinary move-table list, but it must not
/// scroll like one: every rest position places exactly one whole game card
/// against the top of the panel — the edge that sits right under the board's
/// bottom player row. Dragging stays linear (as it does in a `PageView`); the
/// settle is quantised.
///
/// Two things make that possible:
/// * every card is the same height ([ExplorerGameCardGeometry]), so the page
///   grid is `anchor + index * pageExtent`;
/// * the list reserves `pageHeight - pageExtent` of bottom padding, which puts
///   `maxScrollExtent` exactly on the last card's aligned offset.
///
/// Everything here is pure so the grid can be locked by tests.

/// Fixed vertical geometry of one inline explorer game card.
///
/// Nothing in here may depend on the text a particular card happens to hold —
/// a card that grows with its content would knock the whole grid out of step.
class ExplorerGameCardGeometry {
  const ExplorerGameCardGeometry._();

  /// Mini-board edge when the panel has room for it.
  static double get preferredBoardSize => 124.sp;

  /// Smallest board worth shrinking to. Below this the card is unreadable and
  /// paging is abandoned in favour of ordinary scrolling.
  static double get minimumBoardSize => 84.sp;

  /// One continuation chip: its own vertical padding plus a single text line.
  ///
  /// [scaler] is the reader's text-size setting. It has to be part of the
  /// height or a large setting would push the chips past a band sized for the
  /// default one and get them clipped.
  static double chipHeight([TextScaler scaler = TextScaler.noScaling]) =>
      8.h + scaler.scale(12.f) * (20 / 12);

  /// The continuation strip under the board row. Fixed so a long line, a short
  /// line and "no continuation" all occupy the same band.
  static double stripHeight([TextScaler scaler = TextScaler.noScaling]) =>
      16.sp + chipHeight(scaler);

  /// Card height minus the mini-board edge: the board's vertical padding, the
  /// card's own borders, and the continuation strip.
  static double chromeHeight([TextScaler scaler = TextScaler.noScaling]) =>
      20.sp + 3.0 + stripHeight(scaler);

  /// Space under each card — the gap between two cards, and the breathing room
  /// under the last one.
  static double get gap => 8.sp;

  /// Width of the evaluation bar drawn flush against the mini-board's left
  /// edge, the same treatment grid game cards use.
  ///
  /// Horizontal only: the bar is exactly as tall as the board, so nothing in
  /// the page grid ([cardHeight] / [pageExtent]) moves. The width comes out of
  /// the player-metadata column on the right, which has room to spare — never
  /// out of the board.
  static double get evalBarWidth => 10.w;

  static double cardHeight(
    double boardSize, [
    TextScaler scaler = TextScaler.noScaling,
  ]) => boardSize + chromeHeight(scaler);

  /// Scroll distance between two consecutive cards.
  static double pageExtent(
    double boardSize, [
    TextScaler scaler = TextScaler.noScaling,
  ]) => cardHeight(boardSize, scaler) + gap;
}

/// Resolved page geometry for the inline games strip.
@immutable
class ExplorerGamesPageMetrics {
  const ExplorerGamesPageMetrics({
    required this.boardSize,
    required this.cardHeight,
    required this.pageExtent,
  });

  final double boardSize;
  final double cardHeight;
  final double pageExtent;
}

/// Sizes a card so exactly one lands whole under the player row.
///
/// [pageHeight] is the panel's height once the games strip has pulled itself
/// up over the engine lines — measured from under the board's bottom player
/// row to the bottom of the window. [navClearance] is the translucent bottom
/// nav plus the home indicator, which the card must clear to count as visible.
///
/// Returns `null` when even [ExplorerGameCardGeometry.minimumBoardSize] cannot
/// be shown whole; the caller then keeps ordinary list scrolling rather than
/// snapping to a card the user cannot fully see.
ExplorerGamesPageMetrics? resolveExplorerGamesPageMetrics({
  required double pageHeight,
  required double navClearance,
  double? preferredBoardSize,
  double? minimumBoardSize,
  double? chromeHeight,
  double? gap,
}) {
  final preferred =
      preferredBoardSize ?? ExplorerGameCardGeometry.preferredBoardSize;
  final minimum = minimumBoardSize ?? ExplorerGameCardGeometry.minimumBoardSize;
  final chrome = chromeHeight ?? ExplorerGameCardGeometry.chromeHeight();
  final bottomGap = gap ?? ExplorerGameCardGeometry.gap;

  if (!pageHeight.isFinite || !navClearance.isFinite) return null;

  // Room for the card itself: the panel, less the nav it must clear, less the
  // gap that keeps it off that nav's edge.
  final budget = pageHeight - navClearance - bottomGap;
  final boardBudget = budget - chrome;
  if (boardBudget < minimum) return null;

  final boardSize = boardBudget < preferred ? boardBudget : preferred;
  final cardHeight = boardSize + chrome;
  return ExplorerGamesPageMetrics(
    boardSize: boardSize,
    cardHeight: cardHeight,
    pageExtent: cardHeight + bottomGap,
  );
}

/// Bottom padding that puts `maxScrollExtent` exactly on the last card's
/// aligned offset, so the final page tops out under the player row like every
/// other page instead of stopping short.
double explorerGamesListBottomPadding({
  required double pageHeight,
  required double pageExtent,
  required double navClearance,
}) {
  final aligned = pageHeight - pageExtent;
  return aligned > navClearance ? aligned : navClearance;
}

/// Whether the games strip should pin, from content-space geometry alone.
///
/// [delta] is `gamesTop - listTop` (or the equivalent `anchor - pixels`): ≤0
/// means the section top is at or above the panel top. Enter/exit use a small
/// hysteresis band so a 1px jitter cannot flip the mode.
bool explorerGamesPinDecision({
  required double delta,
  required bool currentlyInGames,
  double enterPx = 8,
  double exitPx = 12,
}) {
  return currentlyInGames ? delta <= exitPx : delta <= enterPx;
}

/// Content-space delta matching what the panel measures via `localToGlobal`:
/// positive while the section sits below the panel top.
double explorerGamesPinDelta({
  required double pixels,
  required double anchor,
}) =>
    anchor - pixels;

/// Which inline game cards are on screen, plus whether the list is standing
/// still — together, everything a card needs to decide if it may evaluate.
@immutable
class ExplorerGamesEvalWindow {
  const ExplorerGamesEvalWindow({
    required this.first,
    required this.last,
    required this.settled,
  });

  const ExplorerGamesEvalWindow.none() : first = 0, last = -1, settled = true;

  final int first;
  final int last;
  final bool settled;

  bool get isEmpty => last < first;

  bool contains(int index) => index >= first && index <= last;

  @override
  bool operator ==(Object other) =>
      other is ExplorerGamesEvalWindow &&
      other.first == first &&
      other.last == last &&
      other.settled == settled;

  @override
  int get hashCode => Object.hash(first, last, settled);

  @override
  String toString() =>
      'ExplorerGamesEvalWindow($first..$last, settled: $settled)';
}

/// Resolves which cards are on screen enough to be worth an evaluation.
ExplorerGamesEvalWindow resolveExplorerGamesEvalWindow({
  required double? anchor,
  required double pixels,
  required double viewportHeight,
  required double pageExtent,
  required double cardHeight,
  required int cardCount,
  bool settled = true,
  double minVisibleFraction = 0.5,
}) {
  const empty = ExplorerGamesEvalWindow.none();
  if (anchor == null || cardCount <= 0) return empty;
  if (!anchor.isFinite || !pixels.isFinite || !viewportHeight.isFinite) {
    return empty;
  }
  if (pageExtent <= 0 || cardHeight <= 0 || viewportHeight <= 0) return empty;

  final top = pixels;
  final bottom = pixels + viewportHeight;

  double cardTop(int index) => anchor + index * pageExtent;
  double visibleHeight(int index) {
    final start = cardTop(index);
    final end = start + cardHeight;
    final visible = (end < bottom ? end : bottom) - (start > top ? start : top);
    return visible > 0 ? visible : 0;
  }

  var first = ((top - anchor - cardHeight) / pageExtent).floor() + 1;
  var last = ((bottom - anchor) / pageExtent).ceil() - 1;
  if (first < 0) first = 0;
  if (last > cardCount - 1) last = cardCount - 1;
  if (first > last) return empty;

  final wanted = cardHeight * minVisibleFraction;
  final threshold = wanted < viewportHeight ? wanted : viewportHeight;
  while (first <= last && visibleHeight(first) < threshold) {
    first++;
  }
  while (last >= first && visibleHeight(last) < threshold) {
    last--;
  }
  if (first > last) return empty;

  return ExplorerGamesEvalWindow(first: first, last: last, settled: settled);
}

/// Paint-vs-content mismatch: `visualDelta - (anchor - pixels)`.
///
/// Zero when content-space math matches the painted section top. Non-zero when
/// layout chrome leaves a residual — that residual must ride *inside* the snap
/// target so the motor spring lands flush in one take (never a post-land jump).
double explorerGamesVisualBias({
  required double visualDelta,
  required double pixels,
  required double anchor,
}) =>
    visualDelta - (anchor - pixels);

/// Scroll offset the settle should land on, or `null` to leave the gesture to
/// ordinary list physics.
///
/// Page selection mirrors `PageScrollPhysics`: a flick moves exactly one card
/// from wherever the drag started, a slow release falls back to the nearest.
/// Offsets above the strip belong to the move table, which scrolls normally.
///
/// [visualBias] shifts every page target so the painted card top meets the
/// panel top (see [explorerGamesVisualBias]).
double? explorerGamesSnapTarget({
  required double pixels,
  required double velocity,
  required double velocityTolerance,
  required double anchor,
  required double pageExtent,
  required int pageCount,
  required double minScrollExtent,
  required double maxScrollExtent,
  double visualBias = 0,
}) {
  if (pageExtent <= 0 || pageCount <= 0) return null;
  if (!pixels.isFinite || !anchor.isFinite) return null;

  // Choose the page in content-space (bias does not change which card a flick
  // selects — only where that card's top paints under the panel).
  var page = (pixels - anchor) / pageExtent;
  if (velocity < -velocityTolerance) {
    page -= 0.5;
  } else if (velocity > velocityTolerance) {
    page += 0.5;
  }

  // Still in (or heading back into) the move table — hands off.
  if (page < -0.5) return null;

  final index = page.round().clamp(0, pageCount - 1);
  final target = anchor + index * pageExtent + visualBias;

  // The top of the list is a rest position too. Without it, a move table
  // shorter than one card would be pulled back down onto the first card every
  // time the user let go, and its top rows could never be read.
  if (index == 0 && anchor > minScrollExtent) {
    final biased =
        pixels +
        (velocity > velocityTolerance
            ? pageExtent / 2
            : velocity < -velocityTolerance
            ? -pageExtent / 2
            : 0);
    final topRest = minScrollExtent;
    final firstRest = (anchor + visualBias).clamp(
      minScrollExtent,
      maxScrollExtent,
    );
    if ((biased - topRest).abs() < (biased - firstRest).abs()) {
      return topRest;
    }
  }
  return target.clamp(minScrollExtent, maxScrollExtent);
}

/// Live page grid shared between the panel (which measures it) and the physics
/// (which reads it mid-gesture). Mutable on purpose: `ScrollPhysics` instances
/// are rebuilt by `applyTo` and cannot carry state of their own.
class ExplorerGamesSnapConfig {
  /// Scroll offset at which the first card's top meets the panel's top edge.
  double? anchor;

  /// Distance between two consecutive cards.
  double pageExtent = 0;

  /// Number of cards currently rendered in the strip.
  int pageCount = 0;

  /// Paint residual folded into every snap target (see [explorerGamesVisualBias]).
  double visualBias = 0;

  bool get isActive =>
      anchor != null && anchor!.isFinite && pageExtent > 0 && pageCount > 0;

  /// Returns true when the page grid itself moved (not mere bias noise).
  bool update({
    required double? anchor,
    required double pageExtent,
    required int pageCount,
    double? visualBias,
  }) {
    final anchorMoved =
        (this.anchor == null) != (anchor == null) ||
        (anchor != null && (this.anchor! - anchor).abs() > 0.5);
    final extentMoved = (this.pageExtent - pageExtent).abs() > 0.5;
    final countMoved = this.pageCount != pageCount;
    this.anchor = anchor;
    this.pageExtent = pageExtent;
    this.pageCount = pageCount;
    if (visualBias != null && visualBias.isFinite) {
      // Keep bias on-scale so a bad mid-layout measure cannot fling the strip.
      final cap = pageExtent > 0 ? pageExtent : 64.0;
      this.visualBias = visualBias.clamp(-cap, cap);
    }
    return anchorMoved || extentMoved || countMoved;
  }
}

/// Which card is resting against the top of the panel at [pixels], or null when
/// the offset is still up in the move table.
int? explorerGamesPageAtTop({
  required double pixels,
  required double anchor,
  required double pageExtent,
  required int pageCount,
  bool preferEarlier = false,
}) {
  if (pageExtent <= 0 || pageCount <= 0) return null;
  if (!pixels.isFinite || !anchor.isFinite) return null;
  if (pixels < anchor - pageExtent / 2) return null;
  final raw = (pixels - anchor) / pageExtent;
  if (preferEarlier) {
    return (raw + 0.25).floor().clamp(0, pageCount - 1);
  }
  return raw.round().clamp(0, pageCount - 1);
}

/// Scroll offset that places [pageIndex] flush under the panel top, clamped to
/// the scrollable range.
double explorerGamesOffsetForPage({
  required int pageIndex,
  required double anchor,
  required double pageExtent,
  required double minScrollExtent,
  required double maxScrollExtent,
  double visualBias = 0,
}) {
  final raw = anchor + pageIndex * pageExtent + visualBias;
  if (raw < minScrollExtent) return minScrollExtent;
  if (raw > maxScrollExtent) return maxScrollExtent;
  return raw;
}

/// True when a standstill snap from [pixels] would land on a different page
/// than [settledPage].
bool explorerGamesSettleWouldRetarget({
  required double pixels,
  required double anchor,
  required double pageExtent,
  required int pageCount,
  required int settledPage,
  required double minScrollExtent,
  required double maxScrollExtent,
  double visualBias = 0,
}) {
  final target = explorerGamesSnapTarget(
    pixels: pixels,
    velocity: 0,
    velocityTolerance: 1,
    anchor: anchor,
    pageExtent: pageExtent,
    pageCount: pageCount,
    minScrollExtent: minScrollExtent,
    maxScrollExtent: maxScrollExtent,
    visualBias: visualBias,
  );
  if (target == null) return false;
  final settled = explorerGamesOffsetForPage(
    pageIndex: settledPage,
    anchor: anchor,
    pageExtent: pageExtent,
    minScrollExtent: minScrollExtent,
    maxScrollExtent: maxScrollExtent,
    visualBias: visualBias,
  );
  return (target - settled).abs() > 0.5;
}

/// Whether a post-gesture spring pass should run (mid-card rest only).
bool explorerGamesNeedsPostSettleAlign({
  required double pixels,
  required double anchor,
  required double pageExtent,
  required int pageCount,
  required double minScrollExtent,
  required double maxScrollExtent,
  double visualBias = 0,
  double tolerance = 2.0,
}) {
  final target = explorerGamesSnapTarget(
    pixels: pixels,
    velocity: 0,
    velocityTolerance: 1,
    anchor: anchor,
    pageExtent: pageExtent,
    pageCount: pageCount,
    minScrollExtent: minScrollExtent,
    maxScrollExtent: maxScrollExtent,
    visualBias: visualBias,
  );
  if (target == null) return false;
  return (target - pixels).abs() > tolerance;
}

/// Minimum anchor shift (px) worth absorbing into the scroll offset.
const double kExplorerGamesAnchorCompensateMin = 8.0;

/// How much to add to scroll pixels so the nearest card top meets the panel
/// top, given measured [visualDelta] (`gamesTop - listTop`).
double explorerGamesVisualFlushAdjustment({
  required double visualDelta,
  required double pageExtent,
  required int pageCount,
}) {
  if (pageExtent <= 0 || pageCount <= 0) return 0;
  final index = (-visualDelta / pageExtent).round().clamp(0, pageCount - 1);
  return visualDelta + index * pageExtent;
}

/// Motor spring for the page settle — bounce-free so one take lands on the
/// page without overshoot. Duration stays short so a flick still reads as a
/// decisive page turn. Used by [ExplorerGamesSnapPhysics] via [description]
/// + scroll-pixel [Tolerance] (motor's own tolerance is too tight for px).
const CupertinoMotion kExplorerPageMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 320),
);

/// Quantises the settle of the explorer list onto the games page grid.
class ExplorerGamesSnapPhysics extends ScrollPhysics {
  const ExplorerGamesSnapPhysics({required this.config, super.parent});

  final ExplorerGamesSnapConfig config;

  @override
  ExplorerGamesSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      ExplorerGamesSnapPhysics(config: config, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (!config.isActive || position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tolerance = toleranceFor(position);
    final target = explorerGamesSnapTarget(
      pixels: position.pixels,
      velocity: velocity,
      velocityTolerance: tolerance.velocity,
      anchor: config.anchor!,
      pageExtent: config.pageExtent,
      pageCount: config.pageCount,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
      visualBias: config.visualBias,
    );
    if (target == null) {
      return super.createBallisticSimulation(position, velocity);
    }

    if ((target - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    // Motor spring at scroll tolerance with snapToEnd — one take, exact land.
    return SpringSimulation(
      kExplorerPageMotion.description,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
      snapToEnd: true,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
