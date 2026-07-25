import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// Deterministic paging for the opening explorer's inline games strip.
///
/// Moves table + game cards share one [ListView]. Dragging is linear; on
/// release, [ExplorerGamesSnapPhysics] runs **one** motor spring onto the page
/// grid. No post-frame / post-paint correction — the ballistic target is final.
///
/// Page grid: `anchor + index * pageExtent`, with bottom padding so
/// `maxScrollExtent` sits on the last page.

/// Fixed vertical geometry of one inline explorer game card.
class ExplorerGameCardGeometry {
  const ExplorerGameCardGeometry._();

  static double get preferredBoardSize => 124.sp;
  static double get minimumBoardSize => 84.sp;

  static double chipHeight([TextScaler scaler = TextScaler.noScaling]) =>
      8.h + scaler.scale(12.f) * (20 / 12);

  static double stripHeight([TextScaler scaler = TextScaler.noScaling]) =>
      16.sp + chipHeight(scaler);

  static double chromeHeight([TextScaler scaler = TextScaler.noScaling]) =>
      20.sp + 3.0 + stripHeight(scaler);

  static double get gap => 8.sp;

  static double get evalBarWidth => 10.w;

  static double cardHeight(
    double boardSize, [
    TextScaler scaler = TextScaler.noScaling,
  ]) => boardSize + chromeHeight(scaler);

  static double pageExtent(
    double boardSize, [
    TextScaler scaler = TextScaler.noScaling,
  ]) => cardHeight(boardSize, scaler) + gap;
}

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

double explorerGamesListBottomPadding({
  required double pageHeight,
  required double pageExtent,
  required double navClearance,
}) {
  final aligned = pageHeight - pageExtent;
  return aligned > navClearance ? aligned : navClearance;
}

bool explorerGamesPinDecision({
  required double delta,
  required bool currentlyInGames,
  double enterPx = 8,
  double exitPx = 12,
}) {
  return currentlyInGames ? delta <= exitPx : delta <= enterPx;
}

double explorerGamesPinDelta({
  required double pixels,
  required double anchor,
}) =>
    anchor - pixels;

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

/// Scroll offset the settle should land on, or `null` for free list physics
/// (still up in the move table).
///
/// One list: moves + games. A flick moves **at most one card from where the
/// gesture began** ([gestureStartPixels]).
///
/// [allowPastFirstCard]: until the user has rested on card 0 once, every settle
/// into the strip is forced to card 0. Short move tables put card 0 already
/// high; a fast fling would otherwise overshoot to card 1. The motor spring
/// still decelerates smoothly to that target in one take.
double? explorerGamesSnapTarget({
  required double pixels,
  required double velocity,
  required double velocityTolerance,
  required double anchor,
  required double pageExtent,
  required int pageCount,
  required double minScrollExtent,
  required double maxScrollExtent,
  double? gestureStartPixels,
  bool allowPastFirstCard = true,
}) {
  if (pageExtent <= 0 || pageCount <= 0) return null;
  if (!pixels.isFinite || !anchor.isFinite) return null;

  final origin =
      (gestureStartPixels != null && gestureStartPixels.isFinite)
          ? gestureStartPixels
          : pixels;
  final originPage = (origin - anchor) / pageExtent;
  final currentPage = (pixels - anchor) / pageExtent;

  int index;
  if (velocity > velocityTolerance) {
    // One step down from gesture origin.
    index = originPage.floor() + 1;
  } else if (velocity < -velocityTolerance) {
    index = originPage.ceil() - 1;
  } else {
    // Slow release: nearest to where the finger let go.
    if (currentPage < -0.5) return null;
    index = currentPage.round();
  }

  if (index < 0) {
    if (velocity > velocityTolerance) {
      index = 0;
    } else {
      return null;
    }
  }

  var clamped = index.clamp(0, pageCount - 1);
  // First visit: always land on card 0 (smooth motor decelerate), never skip.
  if (!allowPastFirstCard && clamped > 0) {
    clamped = 0;
  }

  final target = anchor + clamped * pageExtent;

  // Top of the list is also a rest (short move table must stay reachable).
  if (clamped == 0 && anchor > minScrollExtent) {
    final biased =
        pixels +
        (velocity > velocityTolerance
            ? pageExtent / 2
            : velocity < -velocityTolerance
            ? -pageExtent / 2
            : 0);
    if ((biased - minScrollExtent).abs() < (biased - target).abs()) {
      return minScrollExtent;
    }
  }
  return target.clamp(minScrollExtent, maxScrollExtent);
}

/// Live page grid the physics reads mid-gesture.
class ExplorerGamesSnapConfig {
  double? anchor;
  double pageExtent = 0;
  int pageCount = 0;

  /// Scroll offset when the current drag/fling began.
  double? gestureStartPixels;

  /// False until a settle has landed on card 0. Blocks skipping the first card
  /// when a short move table already shows it high on screen.
  bool hasRestedOnFirstCard = false;

  bool get isActive =>
      anchor != null && anchor!.isFinite && pageExtent > 0 && pageCount > 0;

  void noteGestureStart(double pixels) {
    if (pixels.isFinite) gestureStartPixels = pixels;
  }

  void clearGestureStart() {
    gestureStartPixels = null;
  }

  /// Call with live pixels so returning to the move table re-arms the gate.
  void noteLivePixels(double pixels) {
    if (!isActive || !pixels.isFinite) return;
    final page = (pixels - anchor!) / pageExtent;
    if (page < -0.5) {
      hasRestedOnFirstCard = false;
    }
  }

  void markRestedOnFirstCard() {
    hasRestedOnFirstCard = true;
  }

  bool update({
    required double? anchor,
    required double pageExtent,
    required int pageCount,
  }) {
    final anchorMoved =
        (this.anchor == null) != (anchor == null) ||
        (anchor != null && (this.anchor! - anchor).abs() > 0.5);
    final extentMoved = (this.pageExtent - pageExtent).abs() > 0.5;
    final countMoved = this.pageCount != pageCount;
    this.anchor = anchor;
    this.pageExtent = pageExtent;
    this.pageCount = pageCount;
    return anchorMoved || extentMoved || countMoved;
  }
}

int? explorerGamesPageAtTop({
  required double pixels,
  required double anchor,
  required double pageExtent,
  required int pageCount,
}) {
  if (pageExtent <= 0 || pageCount <= 0) return null;
  if (!pixels.isFinite || !anchor.isFinite) return null;
  if (pixels < anchor - pageExtent / 2) return null;
  return ((pixels - anchor) / pageExtent).round().clamp(0, pageCount - 1);
}

double explorerGamesOffsetForPage({
  required int pageIndex,
  required double anchor,
  required double pageExtent,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  final raw = anchor + pageIndex * pageExtent;
  if (raw < minScrollExtent) return minScrollExtent;
  if (raw > maxScrollExtent) return maxScrollExtent;
  return raw;
}

bool explorerGamesSettleWouldRetarget({
  required double pixels,
  required double anchor,
  required double pageExtent,
  required int pageCount,
  required int settledPage,
  required double minScrollExtent,
  required double maxScrollExtent,
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
  );
  if (target == null) return false;
  final settled = explorerGamesOffsetForPage(
    pageIndex: settledPage,
    anchor: anchor,
    pageExtent: pageExtent,
    minScrollExtent: minScrollExtent,
    maxScrollExtent: maxScrollExtent,
  );
  return (target - settled).abs() > 0.5;
}

bool explorerGamesNeedsPostSettleAlign({
  required double pixels,
  required double anchor,
  required double pageExtent,
  required int pageCount,
  required double minScrollExtent,
  required double maxScrollExtent,
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
  );
  if (target == null) return false;
  return (target - pixels).abs() > tolerance;
}

/// Bounce-free motor spring for the **only** settle path (ballistic on release).
const CupertinoMotion kExplorerPageMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 320),
);

/// One ListView settle: motor spring onto the games page grid.
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
      gestureStartPixels: config.gestureStartPixels,
      allowPastFirstCard: config.hasRestedOnFirstCard,
    );
    // Gesture origin is only for this settle.
    config.clearGestureStart();

    if (target == null) {
      // Free-scrolling the move table — re-arm first-card gate.
      config.noteLivePixels(position.pixels);
      return super.createBallisticSimulation(position, velocity);
    }

    // Landing on card 0 unlocks paging to later cards on the next gesture.
    final pageAtTarget =
        ((target - config.anchor!) / config.pageExtent).round();
    if (pageAtTarget <= 0) {
      config.markRestedOnFirstCard();
    }

    if ((target - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }

    // Motor spring decelerates from the (possibly fast) release into the
    // forced first-card target in one smooth take.
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
