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

/// Card a settle should land on, or `null` to hand the settle back to ordinary
/// list physics (the reader is still up in the move table).
///
/// The decision comes from the card the list was **resting** on when the
/// gesture began — never from the offset the finger released at, and never
/// from the offset a mid-flight relayout left behind.
///
/// That is the whole fix for the skipped first card. Landing on card 0 pins the
/// strip, which collapses the engine PV and the move-column header; both are
/// animated, so this list's viewport changes on every frame for a few hundred
/// milliseconds. Each of those frames re-enters
/// `BallisticScrollActivity.applyNewDimensions` → `goBallistic`, so the settle
/// is re-decided from pixels that are by then already inside card 1 — and the
/// strip steps to it. A resting-card decision is the same answer every time it
/// is asked, however many times the ballistic restarts.
///
/// [restingPage] is `null` while the reader is in the move table, so the first
/// settle that enters the strip is card 0 at any finger speed.
int? explorerGamesSnapPage({
  required double pixels,
  required double velocity,
  required double velocityTolerance,
  required double anchor,
  required double pageExtent,
  required int pageCount,
  required int? restingPage,
  double entryMagnet = 0.25,
}) {
  if (pageExtent <= 0 || pageCount <= 0) return null;
  if (!pixels.isFinite || !anchor.isFinite) return null;

  final page = (pixels - anchor) / pageExtent;
  final movingDown = velocity > velocityTolerance;
  final movingUp = velocity < -velocityTolerance;
  final lastPage = pageCount - 1;

  if (restingPage == null) {
    // Coming out of the move table. Entering the strip is *always* card 0: a
    // short move table paints card 0 high on screen, so a normal-pace finger
    // releases well inside card 1 and every offset-derived rule picks it.
    if (movingDown) return 0;
    if (movingUp) return null;
    // Released dead: magnet into card 0 only once it is nearly at the top,
    // so the last move rows stay readable just above it.
    return page >= -entryMagnet ? 0 : null;
  }

  // In the strip: a flick is exactly one card, in the direction thrown.
  if (movingDown) return (restingPage + 1).clamp(0, lastPage);
  if (movingUp) {
    return restingPage == 0 ? null : (restingPage - 1).clamp(0, lastPage);
  }

  // Released dead: the card the finger actually left on top.
  final nearest = page.round();
  if (nearest < 0) return null;
  return nearest.clamp(0, lastPage);
}

/// Card the list is genuinely parked on, or `null` when it is resting anywhere
/// else (in the move table, or part-way between two cards).
///
/// Strict on purpose: "nearly card 0" is not card 0. Calling a settle that
/// stopped short of the anchor a rest on card 0 is what would let the next
/// flick step to card 1 while card 0 had never actually been flush under the
/// player row.
int? explorerGamesRestingPage({
  required double pixels,
  required double anchor,
  required double pageExtent,
  required int pageCount,
  required double minScrollExtent,
  required double maxScrollExtent,
  double tolerance = 4.0,
}) {
  if (pageExtent <= 0 || pageCount <= 0) return null;
  if (!pixels.isFinite || !anchor.isFinite) return null;
  final page = ((pixels - anchor) / pageExtent).round();
  if (page < 0 || page > pageCount - 1) return null;
  // Compare against the *clamped* offset: the last card tops out on
  // `maxScrollExtent`, which the pin's viewport growth can pull in short of
  // its aligned offset. That is still a rest on the last card.
  final offset = explorerGamesOffsetForPage(
    pageIndex: page,
    anchor: anchor,
    pageExtent: pageExtent,
    minScrollExtent: minScrollExtent,
    maxScrollExtent: maxScrollExtent,
  );
  return (offset - pixels).abs() <= tolerance ? page : null;
}

/// Live page grid plus the paging state the physics decides from.
class ExplorerGamesSnapConfig {
  double? anchor;
  double pageExtent = 0;
  int pageCount = 0;

  /// Card the list is parked on, or null while the reader is in the move
  /// table. Written only at a standstill ([endGesture]).
  int? restingPage;

  /// The settle target, held for as long as one settle lasts. A relayout
  /// restarts the in-flight ballistic; every restart must reuse this answer
  /// rather than re-derive one from pixels that have already moved on.
  bool _settleLatched = false;
  int? _latchedPage;

  /// True while a settle spring is actually running toward a card.
  ///
  /// This is the strip's commitment, and the chrome above it reads it: the
  /// engine lines start collapsing the moment the card is chosen, so the space
  /// opens as the card rises into it. Waiting for the offset to arrive instead
  /// plays the two as separate movements — the card lands, and only then does
  /// the room above it appear.
  bool settleRunningToCard = false;

  bool get isActive =>
      anchor != null && anchor!.isFinite && pageExtent > 0 && pageCount > 0;

  /// Finger down: the settle this gesture ends in is decided fresh.
  ///
  /// [restingPage] is deliberately *not* re-read from pixels here. Catching a
  /// list that is still flying must not promote wherever it was caught into a
  /// rest, or the next flick would step off that and skip the card the
  /// interrupted settle was on its way to.
  void beginGesture() {
    _settleLatched = false;
    _latchedPage = null;
    settleRunningToCard = false;
  }

  /// Standstill: this is the only place a rest is recorded.
  void endGesture({
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
  }) {
    _settleLatched = false;
    _latchedPage = null;
    settleRunningToCard = false;
    if (!isActive || !pixels.isFinite) {
      restingPage = null;
      return;
    }
    restingPage = explorerGamesRestingPage(
      pixels: pixels,
      anchor: anchor!,
      pageExtent: pageExtent,
      pageCount: pageCount,
      minScrollExtent: minScrollExtent,
      maxScrollExtent: maxScrollExtent,
    );
  }

  /// A new position / a new set of cards: the reader enters the strip again,
  /// so the next settle owes them the first card.
  void resetPaging() {
    restingPage = null;
    _settleLatched = false;
    _latchedPage = null;
    settleRunningToCard = false;
  }

  /// Target card for the settle now starting, latched for its whole life.
  int? resolveSettlePage({
    required double pixels,
    required double velocity,
    required double velocityTolerance,
  }) {
    if (_settleLatched) return _latchedPage;
    final page = explorerGamesSnapPage(
      pixels: pixels,
      velocity: velocity,
      velocityTolerance: velocityTolerance,
      anchor: anchor!,
      pageExtent: pageExtent,
      pageCount: pageCount,
      restingPage: restingPage,
    );
    _settleLatched = true;
    _latchedPage = page;
    return page;
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
    // A different strip (or a different move table above it) is a different
    // grid, so the card the reader was on no longer means anything. Sub-pixel
    // re-measures must NOT reset it — that would re-arm the entry rule on
    // every scroll notification and the strip could never leave card 0.
    final gridReplaced =
        countMoved ||
        (anchor != null &&
            this.anchor != null &&
            (this.anchor! - anchor).abs() > 8.0);
    // Keep last good geometry if a mid-layout measure fails: an inactive
    // config falls through to free physics, which skips the card entirely.
    if (anchor != null) this.anchor = anchor;
    if (pageExtent > 0) this.pageExtent = pageExtent;
    if (pageCount > 0) this.pageCount = pageCount;
    if (gridReplaced) resetPaging();
    return anchorMoved || extentMoved || countMoved;
  }
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

  /// Bleeds off drag that would push past the first card while the reader is
  /// still coming out of the move table, so the finger decelerates into card 0
  /// and the settle spring has a short way home.
  ///
  /// A progressive damp, never a hard ceiling: a ceiling has to report
  /// overscroll, and overscroll makes `BallisticScrollActivity.applyMoveTo`
  /// fail, which calls `goIdle()` — killing the very spring that was landing
  /// the card and parking the list part-way onto it.
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (!config.isActive || config.restingPage != null) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    final first = config.anchor!;
    final extent = config.pageExtent;
    // offset > 0 ⇒ content moves up (user dragging down the list).
    if (extent <= 0 || offset <= 0 || position.pixels <= first) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    final over = ((position.pixels - first) / extent).clamp(0.0, 1.0);
    return offset * (1.0 - 0.6 * over);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (!config.isActive || position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tolerance = toleranceFor(position);
    final page = config.resolveSettlePage(
      pixels: position.pixels,
      velocity: velocity,
      velocityTolerance: tolerance.velocity,
    );
    // Still in the move table: ordinary list physics own this one.
    if (page == null) {
      config.settleRunningToCard = false;
      return super.createBallisticSimulation(position, velocity);
    }

    final target = explorerGamesOffsetForPage(
      pageIndex: page,
      anchor: config.anchor!,
      pageExtent: config.pageExtent,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );

    if ((target - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }

    // Entering the strip, cap the approach so a hard fling eases onto card 0
    // instead of shooting past it and being hauled back.
    var springVelocity = velocity;
    if (config.restingPage == null) {
      final cap = config.pageExtent * 2.0;
      springVelocity = springVelocity.clamp(-cap, cap);
    }

    config.settleRunningToCard = true;
    return SpringSimulation(
      kExplorerPageMotion.description,
      position.pixels,
      target,
      springVelocity,
      tolerance: tolerance,
      snapToEnd: true,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
