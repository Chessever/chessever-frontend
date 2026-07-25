import 'dart:ui' show ImageFilter;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/figurine_notation.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:intl/intl.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/responsive_helper.dart';
import '../models/models.dart';
import '../providers/explorer_game_focus_provider.dart';
import '../providers/gamebase_explorer_state.dart';
import 'package:motor/motor.dart';

import '../providers/gamebase_providers.dart';
import '../utils/explorer_games_paging.dart';
import '../utils/explorer_move_sort.dart';
import 'explorer_game_card.dart';
import 'position_games_sheet.dart';

/// Panel transitions that are not gesture-driven: the corrective page settle
/// and the table's height changes.
///
/// Bounce-free by design — a correction must not overshoot a page, and a
/// growing table must not push the rows below it past their resting place. The
/// gesture settle itself is springier; see [kExplorerPageMotion].
const CupertinoMotion _kExplorerSmoothMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 220),
);
final Curve _kExplorerSmoothCurve = _kExplorerSmoothMotion.toCurve;

/// How long the panel takes to stop moving after the games strip pins: the
/// move-column header collapsing here plus the engine PV collapsing above it
/// (`_kExplorerGamesExpandMotion`, 320ms), with a frame of slack.
const Duration _kExplorerGamesSettleDelay = Duration(milliseconds: 360);

const double _kMoveColumnWidth = 74;
const double _kGamesColumnWidth = 84;
const double _kLastColumnWidth = 56;
const double _kColumnGap = 6;

/// Free users see explorer aggregates up to and including the 10th full move
/// (ply 20). `currentMoveNumber` is `ply + 1`, so anything above 20 means the
/// current position is *past* move 10 and premium is required.
const int kFreeExplorerMoveNumberLimit = 20;

/// When this many games (or fewer) remain in the explored position, the panel
/// appends an inline games section under the move table (Trello #984).
const int kExplorerInlineGamesLimit = 10;

/// Backend move statistics are answerable from the FEN alone only through 20
/// played plies (`OPENING_EXPLORER_MAX_INDEXED_PLY` / `MV_MAX_PLY` on the
/// fast path). `currentMoveNumber` is `ply + 1`, so above this the aggregate
/// result is no longer authoritative without a move line: an empty answer can
/// mean "not indexed this deep" rather than "no games".
///
/// Production still needs the full UCI line past this boundary even when the
/// server's exact storage goes to 150 plies — FEN-only queries return empty
/// until deep backfill is complete. Never claim "no games" from aggregates
/// alone past this depth.
const int kExplorerIndexedAggregateMoveNumberLimit = 21;

/// Played plies implied by a 6-field FEN (fullmove + side to move).
///
/// Used when the explorer tree was dropped and `currentMoveNumber` is no
/// longer trustworthy for "are we past the indexed window?" decisions.
int _explorerPliesFromFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length < 6) return 0;
  final turn = parts[1];
  final fullMove = int.tryParse(parts[5]) ?? 1;
  final base = (fullMove - 1) * 2;
  return base + (turn == 'b' ? 1 : 0);
}

/// Empty state for the move table.
///
/// Mirrors the desktop explorer's `_ExplorerEmpty`: an icon, a title that
/// states the outcome, and a line explaining what it means, so a deep or rare
/// position does not read as a broken lookup. Collapses to just the text when
/// the panel is short (the swipe panel can be very short in landscape).
class _ExplorerEmpty extends StatelessWidget {
  const _ExplorerEmpty({
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;

  /// Optional affordance rendered under the message. Used to offer the games
  /// that reached this position when move statistics are unavailable.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final compact = maxHeight.isFinite && maxHeight < 132;
        final ultraCompact = maxHeight.isFinite && maxHeight < 76;

        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: (compact ? 16 : 24).sp,
              vertical: (ultraCompact ? 6 : (compact ? 10 : 24)).sp,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 360.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!ultraCompact) ...[
                    Icon(
                      Icons.menu_book_outlined,
                      size: (compact ? 18 : 24).ic,
                      color: context.colors.textSecondary,
                    ),
                    SizedBox(height: (compact ? 6 : 10).sp),
                  ],
                  Text(
                    title,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: (compact ? 12 : 13).f,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: (compact ? 2 : 4).sp),
                  Text(
                    message,
                    maxLines: compact ? 1 : 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: (compact ? 10.5 : 11).f,
                      height: 1.2,
                    ),
                  ),
                  if (action != null && !ultraCompact) ...[
                    SizedBox(height: (compact ? 8 : 12).sp),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens the games that reached the board position, via the FEN-keyed
/// endpoint that answers at depths the aggregate endpoint cannot.
class _ViewPositionGamesButton extends StatelessWidget {
  const _ViewPositionGamesButton({required this.fen, required this.filters});

  final String fen;
  final GamebaseFilters filters;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder:
              (_) => PositionGamesSheet(
                fen: fen,
                title: 'Games at this position',
                filters: filters,
                useFenEndpoint: true,
              ),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 8.sp),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.list_alt_rounded, size: 14.ic, color: kPrimaryColor),
            SizedBox(width: 6.sp),
            Text(
              'View games',
              style: TextStyle(
                color: kPrimaryColor,
                fontSize: 12.f,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable column header. Cycles ascending -> descending -> unsorted, the
/// same three states the desktop header cycles through. Touch has no hover,
/// so the idle affordance is a permanently dimmed sort glyph rather than the
/// desktop's hover-revealed one.
class _SortHeader extends StatelessWidget {
  const _SortHeader({
    required this.label,
    required this.field,
    required this.align,
    required this.sort,
    required this.onSort,
    this.color,
  });

  final String label;
  final ExplorerMoveSortField field;
  final TextAlign align;
  final ExplorerMoveSort? sort;
  final ValueChanged<ExplorerMoveSortField> onSort;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final active = sort?.field == field;
    final ascending = sort?.ascending ?? true;
    final rightAligned = align == TextAlign.right;

    final children = <Widget>[
      Flexible(
        child: Text(
          label,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                active
                    ? context.colors.textPrimary
                    : (color ?? context.colors.textSecondary),
            fontSize: 11.f,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
      SizedBox(width: 2.sp),
      Icon(
        active
            ? (ascending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded)
            : Icons.unfold_more_rounded,
        size: 11.ic,
        color:
            active
                ? kPrimaryColor
                : context.colors.textSecondary.withValues(alpha: 0.45),
      ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSort(field),
      child: Row(
        mainAxisAlignment:
            rightAligned ? MainAxisAlignment.end : MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rightAligned ? children.reversed.toList() : children,
      ),
    );
  }
}

/// Sync sticky header mode from the games section's position in the list.
///
/// Uses light hysteresis so the Move ↔ Games crossfade does not flicker, but
/// restores chrome as soon as the user scrolls up to the top of the games
/// block (about to re-enter the moves area).
///
/// Must not run during layout/paint: `localToGlobal` reads [RenderBox.size],
/// which asserts when content size changes mid-frame (PV expand, full-line
/// upgrade, ballistic fling). Callers schedule this via post-frame callback.
///
/// [pageAnchor] when non-null is the content-space offset of the games section
/// (same as the page grid). Prefer it over `localToGlobal` so mid-transition
/// viewport motion cannot invent a delta that flips the mode.
void _syncExplorerHeaderMode({
  required GlobalKey gamesSectionKey,
  required ScrollController scrollController,
  required bool currentlyInGames,
  required ValueChanged<bool> setInGames,
  double? pageAnchor,
}) {
  if (!scrollController.hasClients) {
    if (currentlyInGames) setInGames(false);
    return;
  }

  // Absolute top of the scrollable: never keep games mode / expand-over-PV.
  final position = scrollController.position;
  if (position.pixels <= position.minScrollExtent + 1.0) {
    if (currentlyInGames) setInGames(false);
    return;
  }

  final gamesContext = gamesSectionKey.currentContext;
  if (gamesContext == null) {
    if (currentlyInGames) setInGames(false);
    return;
  }
  final gamesBox = gamesContext.findRenderObject();
  if (gamesBox is! RenderBox || !gamesBox.hasSize) {
    if (currentlyInGames) setInGames(false);
    return;
  }

  late final double delta;
  if (pageAnchor != null && pageAnchor.isFinite) {
    // Content-space: stable across the pin's own viewport growth. Equivalent to
    // gamesTop - listTop when both are measured cleanly, but does not jitter
    // while the PV / header collapse is moving the panel on screen.
    delta = explorerGamesPinDelta(
      pixels: position.pixels,
      anchor: pageAnchor,
    );
  } else {
    final scrollContext = position.context.notificationContext;
    if (scrollContext == null) {
      if (currentlyInGames) setInGames(false);
      return;
    }
    final listBox = scrollContext.findRenderObject();
    if (listBox is! RenderBox || !listBox.hasSize) {
      if (currentlyInGames) setInGames(false);
      return;
    }

    // Defensive: never read geometry while the pipeline is still laying out.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      return;
    }

    late final double listTop;
    late final double gamesTop;
    try {
      listTop = listBox.localToGlobal(Offset.zero).dy;
      gamesTop = gamesBox.localToGlobal(Offset.zero).dy;
    } catch (_) {
      // Size access not permitted mid-layout — retry is scheduled by the caller.
      return;
    }
    // delta <= 0  → games section top is at/above the sticky edge (deep in games)
    // delta > 0   → games section top has dropped below the edge (leaving games)
    delta = gamesTop - listTop;
  }

  final next = explorerGamesPinDecision(
    delta: delta,
    currentlyInGames: currentlyInGames,
  );
  if (next == currentlyInGames) return;

  // Enter only at rest. Pinning collapses ~200–300px of chrome above the list;
  // doing that mid-ballistic both captures the wrong card (spring overshoot)
  // and feeds the pin/unpin loop. Wait for the page settle, then pin once.
  if (next && position.isScrollingNotifier.value) return;

  // Leaving games mode is gated on the reader actually scrolling back up.
  //
  // Every oscillation needs both halves: pinning collapses the engine PV and
  // the move-column header, which grows this list's viewport; if that shifts
  // the offset enough to push `delta` past `exitPx`, the strip unpins, the
  // chrome comes back, and it pins again — forever. Pinning is driven by the
  // reader's scroll, but *unpinning* was driven by geometry alone, so the loop
  // could close without anyone touching the screen.
  //
  // `userScrollDirection` is idle unless a drag or its fling is in progress, so
  // requiring it here means a layout change can never unpin on its own. The
  // reader scrolling back toward the move table still does, immediately.
  if (!next && position.userScrollDirection == ScrollDirection.idle) return;

  setInGames(next);
}

/// Scroll offset at which [gamesSectionKey]'s first card meets the top edge of
/// the panel. Null while the section is absent or not laid out yet.
///
/// Read from the viewport rather than accumulated from row heights, so the
/// move table above can be any shape without the games grid drifting.
double? _measureExplorerGamesAnchor(GlobalKey gamesSectionKey) {
  final sectionContext = gamesSectionKey.currentContext;
  if (sectionContext == null) return null;
  final box = sectionContext.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  final viewport = RenderAbstractViewport.maybeOf(box);
  if (viewport == null) return null;
  final offset = viewport.getOffsetToReveal(box, 0).offset;
  return offset.isFinite ? offset : null;
}

/// Panel displaying move statistics for the current position.
/// Shows each possible move with game count and win/draw/loss bar.
class MoveStatisticsPanel extends HookConsumerWidget {
  const MoveStatisticsPanel({
    super.key,
    this.onMove,
    this.listBottomPadding,
    this.gamesPageHeight,
  });

  /// Optional handler for move taps. When supplied, taps invoke this callback
  /// instead of advancing the gamebase explorer's internal state — used when
  /// embedding the panel in the chess board screen so taps play on the user's
  /// game rather than diverging into the explorer's standalone exploration.
  final void Function(String uci)? onMove;

  /// Extra scroll padding under the move/games list so the last rows clear a
  /// floating bottom nav (board `extendBody` / translucent bar). When null,
  /// a small default gap is used.
  final double? listBottomPadding;

  /// Height of this panel once the inline games strip has pulled itself up
  /// over the engine lines — i.e. the space between the board's bottom player
  /// row and the bottom of the window.
  ///
  /// Supplying it turns the games strip into a deterministic page strip: each
  /// rest position puts exactly one whole card against the panel's top edge,
  /// right under that player row. Null keeps ordinary list scrolling (the
  /// standalone Gamebase explorer, tablet landscape).
  final double? gamesPageHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamebaseExplorerProvider);
    final hasStaleData = state.moveAggregates.isNotEmpty;

    // Column ordering is view state: it survives navigation between positions
    // (like desktop) but never leaves this panel.
    final sort = useState<ExplorerMoveSort?>(null);
    void cycleSort(ExplorerMoveSortField field) {
      sort.value = ExplorerMoveSort.cycle(sort.value, field);
    }

    // Collapse the move-column header once inline game cards reach the top.
    // The cards are self-explanatory; keeping another "Games" row wastes the
    // exact vertical space this quick-check mode is meant to recover.
    final scrollController = useScrollController();
    final gamesSectionKey = useMemoized(
      () => GlobalKey(debugLabel: 'explorer_inline_games_section'),
    );
    final headerInGames = useState(false);
    /// Held true while a pin/unpin is reshaping the panel, so the decision
    /// cannot be re-taken from geometry its own transition is still moving.
    final headerModeLocked = useRef(false);
    // Coalesce geometry reads onto the next frame — scroll metrics can change
    // mid-layout (PV expand / line upgrade) and localToGlobal is illegal then.
    final headerSyncScheduled = useRef(false);

    // ── Deterministic games paging ─────────────────────────────────────────
    // One card per page, each landing flush against the panel's top edge.
    final navClearance = listBottomPadding ?? 8.sp;
    final pageMetrics =
        gamesPageHeight == null
            ? null
            : resolveExplorerGamesPageMetrics(
              pageHeight: gamesPageHeight!,
              navClearance: navClearance,
              // Same card geometry the cards themselves resolve, reader's
              // text size included, so the grid matches what is drawn.
              chromeHeight: ExplorerGameCardGeometry.chromeHeight(
                MediaQuery.textScalerOf(context),
              ),
            );
    // Grid the physics reads mid-gesture; the panel keeps it measured.
    final snapConfig = useMemoized(() => ExplorerGamesSnapConfig());
    final snapPhysics = useMemoized(
      () => ExplorerGamesSnapPhysics(config: snapConfig),
      [snapConfig],
    );
    final gamesCardCount = useRef(0);

    // ── Which game cards may evaluate ──────────────────────────────────────
    // The strip is a plain Column, so nothing disposes the cards the reader
    // cannot see. This window does that job: the panel measures it, each card
    // listens, and only the ones on screen rate their position. A notifier
    // rather than state — a scroll must not rebuild the whole move list.
    final evalWindow = useMemoized(
      () => ValueNotifier(const ExplorerGamesEvalWindow.none()),
    );
    useEffect(() => evalWindow.dispose, [evalWindow]);
    final listSettled = useRef(true);
    // Card height when the strip is not paging (standalone explorer, tablet
    // landscape): the cards fall back to the preferred board edge, so their
    // geometry is still constant and the window still resolvable.
    final fallbackCardHeight = ExplorerGameCardGeometry.cardHeight(
      ExplorerGameCardGeometry.preferredBoardSize,
      MediaQuery.textScalerOf(context),
    );

    /// Pulls the resting offset back onto the page grid.
    ///
    /// The physics already quantise a normal settle. This is only for layout
    /// shifts (new cards, fen change, panel height) that leave the list mid-
    /// page without a gesture. Instant [jumpTo] — never [animateTo] — so a
    /// correction cannot fight the ballistic land and read as post-land flicker.
    void alignToNearestPage() {
      if (!snapConfig.isActive || !scrollController.hasClients) return;
      // Mid pin/unpin the offset is still being moved by the layout, so
      // "nearest" would round off a number that has not settled. The captured
      // card is restored at the end of that transition instead.
      if (headerModeLocked.value) return;
      final position = scrollController.position;
      if (position.isScrollingNotifier.value) return;
      if (!explorerGamesNeedsPostSettleAlign(
        pixels: position.pixels,
        anchor: snapConfig.anchor!,
        pageExtent: snapConfig.pageExtent,
        pageCount: snapConfig.pageCount,
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
      )) {
        return;
      }
      final target = explorerGamesSnapTarget(
        pixels: position.pixels,
        velocity: 0,
        velocityTolerance: 1,
        anchor: snapConfig.anchor!,
        pageExtent: snapConfig.pageExtent,
        pageCount: snapConfig.pageCount,
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
      );
      if (target == null) return;
      position.jumpTo(target);
    }

    /// Which card is sitting against the top of the panel right now, or null
    /// when the reader is still up in the move table.
    ///
    /// [forPinCapture] biases toward the earlier page so a ballistic overshoot
    /// past the halfway mark cannot promote the next card at pin time.
    int? pageIndexAtTop({bool forPinCapture = false}) {
      if (!snapConfig.isActive || !scrollController.hasClients) return null;
      return explorerGamesPageAtTop(
        pixels: scrollController.position.pixels,
        anchor: snapConfig.anchor!,
        pageExtent: snapConfig.pageExtent,
        pageCount: snapConfig.pageCount,
        preferEarlier: forPinCapture,
      );
    }

    /// Puts [index] against the top of the panel, whatever the offset says.
    ///
    /// Instant on purpose: this runs at the end of a layout transition to undo
    /// a shift the reader never asked for, so there is nothing to animate — and
    /// an animation here would emit a stream of scroll notifications into the
    /// decision that just settled.
    void jumpToPage(int index) {
      if (!snapConfig.isActive || !scrollController.hasClients) return;
      final position = scrollController.position;
      final target = explorerGamesOffsetForPage(
        pageIndex: index,
        anchor: snapConfig.anchor!,
        pageExtent: snapConfig.pageExtent,
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() < 0.5) return;
      position.jumpTo(target);
    }

    /// Republishes the on-screen window from the live scroll offset.
    ///
    /// Uses the same anchor the page grid rests on, so "which card is under the
    /// player row" and "which card evaluates" can never disagree.
    void publishEvalWindow(double? anchor) {
      final metrics = pageMetrics;
      final cardHeight = metrics?.cardHeight ?? fallbackCardHeight;
      final pageExtent =
          metrics?.pageExtent ?? cardHeight + ExplorerGameCardGeometry.gap;
      final position =
          scrollController.hasClients ? scrollController.position : null;
      evalWindow.value = resolveExplorerGamesEvalWindow(
        anchor: anchor,
        pixels: position?.pixels ?? 0,
        viewportHeight: position?.viewportDimension ?? 0,
        pageExtent: pageExtent,
        cardHeight: cardHeight,
        cardCount: gamesCardCount.value,
        settled: listSettled.value,
      );
    }

    void syncGamesGrid({bool allowAnchorCompensation = true}) {
      final metrics = pageMetrics;
      // Measured for both jobs at once: the grid needs it only while paging,
      // the eval window needs it in every host.
      final previousAnchor = snapConfig.anchor;
      final anchor = _measureExplorerGamesAnchor(gamesSectionKey);
      final changed = snapConfig.update(
        anchor: metrics == null ? null : anchor,
        pageExtent: metrics?.pageExtent ?? 0,
        pageCount: metrics == null ? 0 : gamesCardCount.value,
      );
      publishEvalWindow(anchor);

      // Mid pin/unpin the layout is still moving (PV + header collapse). A
      // mis-measured anchor during that window, if absorbed into the offset,
      // jumps the strip onto the next card — exactly the land-on-second bug.
      // The delayed restore puts the captured index back once geometry is
      // stable; do not compensate while locked.
      if (!allowAnchorCompensation || headerModeLocked.value) return;

      // Absorb only a *real* content-space shift (rows above the strip changing
      // height). The pin itself does not move the anchor (header/PV sit outside
      // the scrollable). Sub-threshold remeasures after every card land — eval
      // window settle, card rebuilds — used to jump by a few pixels and look
      // like post-land flicker on every page turn.
      if (!changed || previousAnchor == null || anchor == null) return;
      if (metrics == null || !scrollController.hasClients) return;
      final position = scrollController.position;
      if (position.isScrollingNotifier.value) return;
      final delta = anchor - previousAnchor;
      if (delta.abs() < kExplorerGamesAnchorCompensateMin) return;
      // Only while the reader is actually in the strip — above it the move
      // table scrolls freely and must not be yanked.
      if (position.pixels <= previousAnchor - metrics.pageExtent) return;
      final compensated = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((compensated - position.pixels).abs() > 0.5) {
        position.jumpTo(compensated);
      }
    }

    void runHeaderModeSync() {
      // Header mode is latched across its own transition.
      //
      // `_syncExplorerHeaderMode` decides from `gamesTop - listTop`, which
      // reduces exactly to `anchor - pixels` — the scroll offset. Pinning
      // collapses the engine PV *and* the move-column header, growing this
      // list's viewport by a couple of hundred pixels; that shrinks
      // `maxScrollExtent`, which can clamp `pixels`, which changes the very
      // measurement the decision was made from. Re-deciding mid-transition
      // pins and unpins forever, and any correction scrolled in during the
      // window feeds the loop rather than settling it.
      //
      // So while the layout is in flight, keep the grid and the eval window
      // fresh but leave the mode alone — and never absorb anchor jitter into
      // the offset until the captured card is restored.
      if (headerModeLocked.value) {
        syncGamesGrid(allowAnchorCompensation: false);
        return;
      }
      _syncExplorerHeaderMode(
        gamesSectionKey: gamesSectionKey,
        scrollController: scrollController,
        currentlyInGames: headerInGames.value,
        // Content-space pin decision — immune to the pin's own viewport growth.
        pageAnchor: snapConfig.anchor,
        setInGames: (v) {
          if (headerInGames.value == v) return;
          // Captured at rest (enter is gated on !isScrolling). preferEarlier is
          // belt-and-braces if a frame of residual motion remains.
          final restoreIndex = v ? pageIndexAtTop(forPinCapture: true) : null;
          headerModeLocked.value = true;
          headerInGames.value = v;
          // Drive games expanded-overlay mode (covers engine lines + table).
          final pinned = ref.read(explorerInlineGamesPinnedProvider);
          if (pinned != v) {
            ref.read(explorerInlineGamesPinnedProvider.notifier).state = v;
          }
          // Put the card under the top edge *now*, before the chrome collapse
          // finishes reshaping maxScrollExtent. Waiting only for the delayed
          // pass let a clamp land the strip on the next page first.
          if (restoreIndex != null) jumpToPage(restoreIndex);
          Future.delayed(_kExplorerGamesSettleDelay, () {
            if (!context.mounted) {
              headerModeLocked.value = false;
              return;
            }
            // Measure only — no compensation jump that could fight restore.
            syncGamesGrid(allowAnchorCompensation: false);
            // Re-assert the captured card once layout has settled (viewport and
            // maxScrollExtent are final). jumpTo is a no-op when already there.
            if (restoreIndex != null &&
                headerInGames.value &&
                scrollController.hasClients) {
              jumpToPage(restoreIndex);
            }
            // Released a frame later so the jump's own notification is consumed
            // while the mode is still latched.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              headerModeLocked.value = false;
            });
          });
        },
      );
      syncGamesGrid();
    }

    void syncHeaderMode() {
      if (headerSyncScheduled.value) return;
      headerSyncScheduled.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        headerSyncScheduled.value = false;
        runHeaderModeSync();
      });
    }

    final alignScheduled = useRef(false);
    void scheduleAlign() {
      if (alignScheduled.value) return;
      alignScheduled.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        alignScheduled.value = false;
        // Measure before correcting: the strip may have grown a card, or the
        // panel may have changed height, since the gesture started.
        syncGamesGrid();
        alignToNearestPage();
      });
    }

    void onGamesCardCountChanged(int count) {
      if (gamesCardCount.value == count) return;
      gamesCardCount.value = count;
      // A different number of cards is a different set of pages, so this is one
      // of the deliberate moments that may re-align. Alignment is never driven
      // by scrolling itself — see [syncGamesGrid].
      scheduleAlign();
    }

    useEffect(() {
      void onScroll() => syncHeaderMode();
      scrollController.addListener(onScroll);
      syncHeaderMode();
      return () {
        scrollController.removeListener(onScroll);
        // Leave chrome unpinned when this panel unmounts.
        Future.microtask(() {
          try {
            ref.read(explorerInlineGamesPinnedProvider.notifier).state = false;
          } catch (_) {}
        });
      };
    }, [scrollController]);

    // Re-measure when the games section mounts/unmounts with data changes.
    useEffect(() {
      syncHeaderMode();
      return null;
    }, [state.totalGames, state.isLoading, state.currentFen]);

    // Grid follows the strip: a new position (or a different card count) is a
    // different set of pages.
    useEffect(() {
      scheduleAlign();
      return null;
    }, [state.currentFen, gamesPageHeight, pageMetrics?.pageExtent]);

    final sortedAggregates = applyExplorerMoveSort(
      state.moveAggregates,
      sort.value,
      state.currentFen,
    );

    final isSubscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    // Mirror `requirePremiumGuard`: bypass in debug so engineers can exercise
    // deep positions without a live RevenueCat subscription.
    final pastFreeLimit =
        state.currentMoveNumber > kFreeExplorerMoveNumberLimit;
    final showGate = pastFreeLimit && !isSubscribed && !kDebugMode;
    // True when the current position is the last free step — the next ply
    // would land past move 10. Used to paywall *before* navigating into the
    // gated zone, rather than letting the user advance and then blurring the
    // panel behind them.
    final nextStepCrossesLimit =
        !isSubscribed &&
        !kDebugMode &&
        state.currentMoveNumber >= kFreeExplorerMoveNumberLimit;

    // First load (or a position change that cleared the table) shows the same
    // header+rows scaffold with shimmering skeleton rows instead of a centered
    // spinner — keeps the layout stable and matches the app's shimmer style.
    final showSkeleton = state.isLoading && !hasStaleData && !showGate;

    // Mirrors the inline-games condition in `_buildListChildren` — the page
    // grid, the bottom reserve and the physics all hinge on the strip really
    // being there.
    final showInlineGames =
        !showGate &&
        !state.isLoading &&
        sortedAggregates.isNotEmpty &&
        state.totalGames > 0 &&
        state.totalGames <= kExplorerInlineGamesLimit;
    final pagesGames = showInlineGames && pageMetrics != null;

    if (state.error != null && !showGate) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16.sp),
          child: Text(
            state.error!,
            style: TextStyle(color: kRedColor, fontSize: 14.f),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (state.moveAggregates.isEmpty && !showGate && !state.isLoading) {
      // Empty aggregates do NOT always mean the position is unknown. Move
      // statistics can only be computed when the client supplies the move
      // line from the initial position, so past the backend's indexed window
      // they come back empty for a transposition, for a board opened at a
      // FEN, and for every position while its deep FEN aggregate index is
      // unavailable — on positions with hundreds of real games behind them.
      //
      // Inside the indexed window the aggregate answer IS authoritative, so
      // only second-guess it past that boundary; that also keeps this from
      // costing an extra request on ordinary empty openings.
      //
      // Depth must be derived from the board FEN (and the explored line), not
      // only `currentMoveNumber`. When a line-drop leaves the explorer tree
      // empty, `currentMoveNumber` collapses to 1 and the old check treated a
      // deep midgame as "inside the indexed window", permanently claiming
      // "No games match this position".
      final pliesFromFen = _explorerPliesFromFen(state.currentFen);
      final pastIndexedWindow =
          state.currentMoveNumber > kExplorerIndexedAggregateMoveNumberLimit ||
          state.exploredMoves.length >=
              kExplorerIndexedAggregateMoveNumberLimit ||
          pliesFromFen >= kExplorerIndexedAggregateMoveNumberLimit;

      if (!pastIndexedWindow) {
        return const _ExplorerEmpty(
          title: 'No games match this position',
          message:
              'No master/online games are indexed for the position on the '
              'board.',
        );
      }

      // Past the boundary, ask the FEN-keyed endpoint before claiming there
      // is nothing here, and offer those games when there are.
      final hasFenGames = ref.watch(
        fenPositionHasGamesProvider(state.currentFen),
      );

      return hasFenGames.maybeWhen(
        data:
            (hasGames) =>
                hasGames
                    ? _ExplorerEmpty(
                      title: 'No move statistics for this position',
                      message:
                          'Move statistics need the full line from the start. '
                          'Games that reached this position are still available.',
                      action: _ViewPositionGamesButton(
                        fen: state.currentFen,
                        filters: state.filters,
                      ),
                    )
                    : const _ExplorerEmpty(
                      title: 'No games match this position',
                      message:
                          'No master/online games are indexed for the position '
                          'on the board.',
                    ),
        // While the check is in flight, say nothing we might have to retract.
        orElse:
            () => const _ExplorerEmpty(
              title: 'No move statistics for this position',
              message: 'Checking for games that reached it…',
            ),
      );
    }

    final movesHeader = Row(
      key: const ValueKey<String>('explorer_header_moves'),
      children: [
        SizedBox(
          width: _kMoveColumnWidth.w,
          child: _SortHeader(
            label: 'Move',
            field: ExplorerMoveSortField.move,
            align: TextAlign.left,
            sort: sort.value,
            onSort: cycleSort,
          ),
        ),
        SizedBox(width: _kColumnGap.sp),
        Expanded(
          child: _SortHeader(
            label: 'Score',
            field: ExplorerMoveSortField.score,
            align: TextAlign.center,
            sort: sort.value,
            onSort: cycleSort,
          ),
        ),
        SizedBox(width: _kColumnGap.sp),
        SizedBox(
          width: _kGamesColumnWidth.w,
          child: Semantics(
            label: 'Sort by games',
            button: true,
            child: _SortHeader(
              label: '',
              field: ExplorerMoveSortField.games,
              align: TextAlign.right,
              sort: sort.value,
              onSort: cycleSort,
              color: kPrimaryColor,
            ),
          ),
        ),
        SizedBox(width: _kColumnGap.sp),
        SizedBox(
          width: _kLastColumnWidth.w,
          child: _SortHeader(
            label: 'Last',
            field: ExplorerMoveSortField.last,
            align: TextAlign.right,
            sort: sort.value,
            onSort: cycleSort,
          ),
        ),
      ],
    );

    final Widget mainContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isLoading)
          LinearProgressIndicator(
            minHeight: 2,
            color: context.colors.textPrimary,
            backgroundColor: Colors.transparent,
          ),
        AnimatedSize(
          duration: _kExplorerSmoothMotion.duration,
          curve: _kExplorerSmoothCurve,
          alignment: Alignment.topCenter,
          child:
              headerInGames.value
                  ? const SizedBox.shrink()
                  : Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.sp,
                          vertical: 6.sp,
                        ),
                        child: movesHeader,
                      ),
                      Divider(color: context.colors.divider, height: 1),
                    ],
                  ),
        ),
        // Move list
        Expanded(
          child: Builder(
            builder: (context) {
              // Clear the bottom nav / home indicator so last move rows and
              // inline game cards are fully scrollable into view. While the
              // strip pages, the reserve is instead whatever puts the *last*
              // card's aligned offset exactly on `maxScrollExtent`, so the
              // final page tops out under the player row like every other one.
              final listPadding = EdgeInsets.only(
                bottom:
                    pagesGames
                        ? explorerGamesListBottomPadding(
                          pageHeight: gamesPageHeight!,
                          pageExtent: pageMetrics.pageExtent,
                          navClearance: navClearance,
                        )
                        : navClearance,
              );
              // Catch every scroll update (including ballistic / edge bounce)
              // so bottom-nav restore isn't missed when flinging up to the
              // top of the games block.
              Widget wrapScroll(Widget child) {
                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // Cards carry a horizontal chip strip; its scrolling says
                    // nothing about where this list is resting.
                    if (notification.metrics.axis != Axis.vertical) {
                      return false;
                    }
                    // Engine jobs wait for a standstill: a card crossing the
                    // viewport mid-fling would only take the next one's turn.
                    final wasSettled = listSettled.value;
                    if (notification is ScrollStartNotification) {
                      listSettled.value = false;
                    } else if (notification is ScrollEndNotification) {
                      listSettled.value = true;
                    }
                    if (listSettled.value != wasSettled) syncHeaderMode();
                    if (notification is ScrollUpdateNotification ||
                        notification is ScrollEndNotification ||
                        notification is OverscrollNotification) {
                      syncHeaderMode();
                    }
                    // Do NOT re-align after every ScrollEnd while paging.
                    // ExplorerGamesSnapPhysics already lands on the grid; a
                    // second animateTo/jump after land is the card-to-card
                    // flicker. Layout-driven scheduleAlign (fen / card count /
                    // page metrics) still covers real mid-page rests.
                    return false;
                  },
                  child: child,
                );
              }

              return showSkeleton
                  ? Skeletonizer(
                    enabled: true,
                    // Match the app-wide loading shimmer: a low-alpha, inactive
                    // grey sweep (see `chess_board_screen_new.dart` variant cards).
                    effect: ShimmerEffect(
                      baseColor: context.colors.textPrimary.withValues(
                        alpha: 0.05,
                      ),
                      highlightColor: context.colors.textPrimary.withValues(
                        alpha: 0.1,
                      ),
                      duration: const Duration(milliseconds: 1500),
                    ),
                    child: wrapScroll(
                      ListView.separated(
                        controller: scrollController,
                        padding: listPadding,
                        itemCount: 7,
                        separatorBuilder:
                            (_, __) => Divider(
                              color: context.colors.divider,
                              height: 1,
                              indent: 12.sp,
                            ),
                        itemBuilder:
                            (_, index) =>
                                _MoveStatisticsSkeletonRow(seed: index),
                      ),
                    ),
                  )
                  : wrapScroll(
                    ListView(
                      controller: scrollController,
                      padding: listPadding,
                      physics: pagesGames ? snapPhysics : null,
                      children: _buildListChildren(
                        context,
                        ref,
                        state,
                        aggregates: sortedAggregates,
                        showGate: showGate,
                        nextStepCrossesLimit: nextStepCrossesLimit,
                        gamesSectionKey: gamesSectionKey,
                        showInlineGames: showInlineGames,
                        gamesBoardSize: pageMetrics?.boardSize,
                        onGamesCardCountChanged: onGamesCardCountChanged,
                        gamesEvalWindow: evalWindow,
                      ),
                    ),
                  );
            },
          ),
        ),
      ],
    );

    if (showGate) {
      return Stack(
        children: [
          mainContent,
          Positioned.fill(
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4),
                  child: GestureDetector(
                    onTap: () => requirePremiumGuard(context, ref),
                    behavior: HitTestBehavior.opaque,
                    child: const _ExplorerPremiumGate(),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return mainContent;
  }

  List<Widget> _buildListChildren(
    BuildContext context,
    WidgetRef ref,
    GamebaseExplorerState state, {
    required List<MoveAggregate> aggregates,
    required bool showGate,
    required bool nextStepCrossesLimit,
    required bool showInlineGames,
    GlobalKey? gamesSectionKey,
    double? gamesBoardSize,
    ValueChanged<int>? onGamesCardCountChanged,
    ValueListenable<ExplorerGamesEvalWindow>? gamesEvalWindow,
  }) {
    Widget divider() =>
        Divider(color: context.colors.divider, height: 1, indent: 12.sp);

    final children = <Widget>[];

    if (aggregates.isEmpty && showGate) {
      for (var i = 0; i < 5; i++) {
        if (i > 0) children.add(divider());
        children.add(const _MoveStatisticsPlaceholderRow());
      }
      return children;
    }

    for (var i = 0; i < aggregates.length; i++) {
      final aggregate = aggregates[i];
      if (i > 0) children.add(divider());
      children.add(
        _MoveStatisticsRow(
          aggregate: aggregate,
          currentFen: state.currentFen,
          exploredMoves: state.exploredMoves,
          filters: state.filters,
          onTap: () async {
            // A move-row tap always releases a focused game card so the
            // arrows return to the main board instantly (Trello #984).
            ref.read(explorerFocusedGameProvider.notifier).clear();
            if (showGate) {
              await requirePremiumGuard(context, ref);
              return;
            }
            if (nextStepCrossesLimit) {
              final unlocked = await requirePremiumGuard(context, ref);
              if (!unlocked) return;
            }
            if (onMove != null) {
              onMove!(aggregate.uci);
            } else {
              ref
                  .read(gamebaseExplorerProvider.notifier)
                  .makeMove(aggregate.uci);
            }
          },
        ),
      );
    }

    // Lichess-style '∑' totals row — hidden when only one move remains.
    if (aggregates.length > 1) {
      children.add(divider());
      children.add(
        _MoveStatisticsSummaryRow(
          aggregates: aggregates,
          currentFen: state.currentFen,
          exploredMoves: state.exploredMoves,
          filters: state.filters,
        ),
      );
    }

    // Inline games section once few enough games remain in this position.
    // The blur gate already covers the whole panel past the free limit, so
    // no extra gating is needed here.
    if (showInlineGames) {
      children.add(divider());
      children.add(
        KeyedSubtree(
          key: gamesSectionKey,
          child: ExplorerGamesSection(
            fen: state.currentFen,
            moves: state.exploredMoves,
            filters: state.filters,
            boardSize: gamesBoardSize,
            onCardCountChanged: onGamesCardCountChanged,
            evalWindow: gamesEvalWindow,
          ),
        ),
      );
    }

    return children;
  }
}

/// Totals row summing every move row above it ('∑'): weighted W/D/L bar,
/// aggregate game count, and the most recent last-played date. Mirrors the
/// per-row column geometry so it reads as part of the table.
class _MoveStatisticsSummaryRow extends StatelessWidget {
  const _MoveStatisticsSummaryRow({
    required this.aggregates,
    required this.currentFen,
    required this.exploredMoves,
    required this.filters,
  });

  final List<MoveAggregate> aggregates;
  final String currentFen;
  final List<String> exploredMoves;
  final GamebaseFilters filters;

  @override
  Widget build(BuildContext context) {
    final summary = MoveAggregatesSummary.fromAggregates(aggregates);
    final moveNumberLabel = explorerMoveNumberLabelFromFen(currentFen);

    void openGames() {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        builder:
            (_) => PositionGamesSheet(
              fen: currentFen,
              moves: exploredMoves,
              // No per-move UCI: all games that reached this explorer position.
              filters: filters,
              title: 'Games for $moveNumberLabel∑',
            ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
      child: Row(
        children: [
          SizedBox(
            width: _kMoveColumnWidth.w,
            child: Row(
              children: [
                Text(
                  moveNumberLabel,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12.f,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(width: 4.w),
                Expanded(
                  child: Text(
                    '∑',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 14.f,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          Expanded(
            child: _StatisticsBar(
              whiteRate: summary.whiteRate,
              drawRate: summary.drawRate,
              blackRate: summary.blackRate,
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          SizedBox(
            width: _kGamesColumnWidth.w,
            child: Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                    message: 'Games',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: openGames,
                        borderRadius: BorderRadius.circular(20.br),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimaryColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20.br),
                            border: Border.all(
                              color: kPrimaryColor.withValues(alpha: 0.45),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Text(
                                  summary.formattedTotal,
                                  textAlign: TextAlign.right,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: kPrimaryColor,
                                    fontSize: 12.f,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              SizedBox(width: 4.w),
                              Icon(
                                Icons.list_alt_rounded,
                                color: kPrimaryColor,
                                size: 15.ic,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(
                    begin: 1.0,
                    end: 1.04,
                    duration: 1200.ms,
                    curve: Curves.easeInOut,
                  ),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          SizedBox(
            width: _kLastColumnWidth.w,
            child: Text(
              _formatLastPlayed(summary.lastPlayed),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.f,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder row for blurred stats teaser.
class _MoveStatisticsPlaceholderRow extends StatelessWidget {
  const _MoveStatisticsPlaceholderRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
      child: Row(
        children: [
          SizedBox(
            width: _kMoveColumnWidth.w,
            child: Row(
              children: [
                Container(
                  width: 20.w,
                  height: 12.h,
                  decoration: BoxDecoration(
                    color: context.colors.textSecondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2.br),
                  ),
                ),
                SizedBox(width: 4.w),
                Container(
                  width: 30.w,
                  height: 14.h,
                  decoration: BoxDecoration(
                    color: context.colors.textSecondary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2.br),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          Expanded(
            child: Container(
              height: 14.h,
              decoration: BoxDecoration(
                color: context.colors.textSecondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16.br),
              ),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          Container(
            width: _kGamesColumnWidth.w,
            height: 12.h,
            decoration: BoxDecoration(
              color: context.colors.textSecondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          Container(
            width: _kLastColumnWidth.w,
            height: 12.h,
            decoration: BoxDecoration(
              color: context.colors.textSecondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmering skeleton row shown during first load / position change. Mirrors
/// the real [_MoveStatisticsRow] column geometry so swapping in live data
/// causes no layout shift; the wrapping [Skeletonizer] paints the grey shimmer
/// over these leaves.
class _MoveStatisticsSkeletonRow extends StatelessWidget {
  const _MoveStatisticsSkeletonRow({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    const sans = ['Nf3', 'e4', 'Bb5', 'd4', 'c4', 'Nc3', 'Bc4'];
    const counts = ['1.2M', '430k', '88k', '21k', '9.4k', '3.1k', '740'];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
      child: Row(
        children: [
          SizedBox(
            width: _kMoveColumnWidth.w,
            child: Row(
              children: [
                Text(
                  '12.',
                  style: TextStyle(fontSize: 12.f, fontWeight: FontWeight.w500),
                ),
                SizedBox(width: 4.w),
                Text(
                  sans[seed % sans.length],
                  style: TextStyle(fontSize: 14.f, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          Expanded(
            child: Container(
              height: 14.h,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16.br),
              ),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          SizedBox(
            width: _kGamesColumnWidth.w,
            child: Text(
              counts[seed % counts.length],
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.f, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          SizedBox(
            width: _kLastColumnWidth.w,
            child: Text(
              '2024',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.f),
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual row showing move statistics.
class _MoveStatisticsRow extends ConsumerWidget {
  const _MoveStatisticsRow({
    required this.aggregate,
    required this.currentFen,
    required this.exploredMoves,
    required this.filters,
    required this.onTap,
  });

  final MoveAggregate aggregate;
  final String currentFen;
  final List<String> exploredMoves;
  final GamebaseFilters filters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (sanMove, _) = uciToSanAndFen(aggregate.uci, currentFen);
    final moveNumberLabel = explorerMoveNumberLabelFromFen(currentFen);

    final useFigurine = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.useFigurine ?? const BoardSettingsNew().useFigurine,
      ),
    );
    final pieceAssets = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.pieceAssets ?? const BoardSettingsNew().pieceAssets,
      ),
    );

    final moveStyle = TextStyle(
      color: context.colors.textPrimary,
      fontSize: 14.f,
      fontWeight: FontWeight.w500,
    );

    void openGames() {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        builder:
            (_) => PositionGamesSheet(
              fen: currentFen,
              moves: exploredMoves,
              uci: aggregate.uci,
              filters: filters,
              title: 'Games for $moveNumberLabel$sanMove',
            ),
      );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
        child: Row(
          children: [
            // Move name
            SizedBox(
              width: _kMoveColumnWidth.w,
              child: Row(
                children: [
                  Text(
                    moveNumberLabel,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12.f,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child:
                        useFigurine
                            ? RichText(
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              text: TextSpan(
                                children: buildFigurineSpans(
                                  text: sanMove,
                                  pieceAssets: pieceAssets,
                                  style: moveStyle,
                                  pieceSize: 16.f,
                                ),
                              ),
                            )
                            : Text(
                              sanMove,
                              style: moveStyle,
                              overflow: TextOverflow.ellipsis,
                            ),
                  ),
                ],
              ),
            ),
            SizedBox(width: _kColumnGap.sp),
            // Statistics bar
            Expanded(
              child: _StatisticsBar(
                whiteRate: aggregate.whiteWinRate,
                drawRate: aggregate.drawRate,
                blackRate: aggregate.blackWinRate,
              ),
            ),
            SizedBox(width: _kColumnGap.sp),
            SizedBox(
              width: _kGamesColumnWidth.w,
              child: Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                      message: 'Games',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: openGames,
                          borderRadius: BorderRadius.circular(20.br),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.w,
                              vertical: 4.h,
                            ),
                            decoration: BoxDecoration(
                              color: kPrimaryColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20.br),
                              border: Border.all(
                                color: kPrimaryColor.withValues(alpha: 0.45),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    aggregate.formattedTotal,
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: kPrimaryColor,
                                      fontSize: 12.f,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 4.w),
                                Icon(
                                  Icons.list_alt_rounded,
                                  color: kPrimaryColor,
                                  size: 15.ic,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(
                      begin: 1.0,
                      end: 1.04,
                      duration: 1200.ms,
                      curve: Curves.easeInOut,
                    ),
              ),
            ),
            SizedBox(width: _kColumnGap.sp),
            SizedBox(
              width: _kLastColumnWidth.w,
              child: Text(
                _formatLastPlayed(aggregate.lastPlayed),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12.f,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatLastPlayed(DateTime? date) {
  if (date == null) return '—';
  return DateFormat('MMM yyyy').format(date);
}

/// Convert UCI move notation to SAN (Standard Algebraic Notation) for display.
String uciToSan(String uci, String fen) {
  try {
    final position = Chess.fromSetup(Setup.parseFen(fen));

    final from = Square.fromName(uci.substring(0, 2));
    final to = Square.fromName(uci.substring(2, 4));
    Role? promotion;
    if (uci.length > 4) {
      promotion = Role.fromChar(uci[4]);
    }

    final move = NormalMove(from: from, to: to, promotion: promotion);
    final result = position.makeSan(move);
    return result.$2;
  } catch (_) {
    return uci;
  }
}

int _fullMoveNumberFromFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length < 6) return 1;
  return int.tryParse(parts[5]) ?? 1;
}

/// Move-number prefix shown before SAN (and the ∑ summary) in the explorer
/// move table: `12.` when White to move, `12...` when Black to move.
///
/// Public so pure-logic tests can lock the SUM-row / move-row label contract.
String explorerMoveNumberLabelFromFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  final isWhite = parts.length < 2 || parts[1] == 'w';
  final fullMove = _fullMoveNumberFromFen(fen);
  return isWhite ? '$fullMove.' : '$fullMove...';
}

/// Like [uciToSan] but also returns the resulting FEN after the move.
/// Returns `(san, resultingFen)`. `resultingFen` is null on parse failure.
(String san, String? resultingFen) uciToSanAndFen(String uci, String fen) {
  try {
    final position = Chess.fromSetup(Setup.parseFen(fen));

    final from = Square.fromName(uci.substring(0, 2));
    final to = Square.fromName(uci.substring(2, 4));
    Role? promotion;
    if (uci.length > 4) {
      promotion = Role.fromChar(uci[4]);
    }

    final move = NormalMove(from: from, to: to, promotion: promotion);
    final result = position.makeSan(move);
    // result.$1 is the new Position, result.$2 is the SAN string
    return (result.$2, result.$1.fen);
  } catch (_) {
    return (uci, null);
  }
}

/// Horizontal bar showing win/draw/loss distribution.
class _StatisticsBar extends StatelessWidget {
  const _StatisticsBar({
    required this.whiteRate,
    required this.drawRate,
    required this.blackRate,
  });

  final double whiteRate;
  final double drawRate;
  final double blackRate;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.br),
      child: SizedBox(
        height: 16.h,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segments = _scoreSegments();
            if (segments.isEmpty || constraints.maxWidth <= 0) {
              return const SizedBox.shrink();
            }

            final widths = _scoreSegmentWidths(
              segments,
              constraints.maxWidth,
              minimumLabelWidth: 28.w,
            );

            return Row(
              children: [
                for (var i = 0; i < segments.length; i++)
                  SizedBox(
                    width: widths[i],
                    child: _ScoreSegment(segment: segments[i]),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<_ScoreSegmentData> _scoreSegments() {
    return [
      if (whiteRate > 0)
        _ScoreSegmentData(
          rate: whiteRate,
          label: _formatScorePercent(whiteRate),
          backgroundColor: kMoveStatWhiteColor,
          textColor: kMoveStatBlackColor,
        ),
      if (drawRate > 0)
        _ScoreSegmentData(
          rate: drawRate,
          label: _formatScorePercent(drawRate),
          backgroundColor: kMoveStatDrawColor,
          textColor: kMoveStatWhiteColor,
        ),
      if (blackRate > 0)
        _ScoreSegmentData(
          rate: blackRate,
          label: _formatScorePercent(blackRate),
          backgroundColor: kMoveStatBlackColor,
          textColor: kMoveStatWhiteColor,
        ),
    ];
  }
}

class _ScoreSegment extends StatelessWidget {
  const _ScoreSegment({required this.segment});

  final _ScoreSegmentData segment;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: segment.backgroundColor,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 1.w),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          segment.label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: segment.textColor,
            fontSize: 10.f,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ScoreSegmentData {
  const _ScoreSegmentData({
    required this.rate,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final double rate;
  final String label;
  final Color backgroundColor;
  final Color textColor;
}

String _formatScorePercent(double rate) =>
    '${(rate * 100).toStringAsFixed(0)}%';

List<double> _scoreSegmentWidths(
  List<_ScoreSegmentData> segments,
  double availableWidth, {
  required double minimumLabelWidth,
}) {
  if (segments.isEmpty || availableWidth <= 0) return const [];

  final safeMinimum = minimumLabelWidth.clamp(
    0.0,
    availableWidth / segments.length,
  );
  final totalRate = segments.fold<double>(
    0,
    (sum, segment) => sum + segment.rate,
  );
  final remainingWidth = availableWidth - (safeMinimum * segments.length);

  if (remainingWidth <= 0 || totalRate <= 0) {
    return List<double>.filled(
      segments.length,
      availableWidth / segments.length,
    );
  }

  final widths = <double>[
    for (final segment in segments)
      safeMinimum + (remainingWidth * (segment.rate / totalRate)),
  ];

  // Remove any sub-pixel drift so the row fills the clipped bar exactly.
  final drift =
      availableWidth - widths.fold<double>(0, (sum, width) => sum + width);
  widths[widths.length - 1] += drift;
  return widths;
}

/// CTA shown in place of the move-aggregate table when the current position
/// is past the 10th full move and the user is not subscribed.
class _ExplorerPremiumGate extends ConsumerWidget {
  const _ExplorerPremiumGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.sp, vertical: 24.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56.w,
              height: 56.h,
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_stories_rounded,
                color: kPrimaryColor,
                size: 28.ic,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Theory ends here. Prep doesn’t.',
              textAlign: TextAlign.center,
              style: AppTypography.textLgBold.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Games are won past book. Unlock Premium to keep mining master '
              'data deep into the middlegame — score trends, sideline '
              'frequency, novelties, and the exact paths titled players take '
              'beyond move 10.',
              textAlign: TextAlign.center,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textSecondary,
                height: 1.35,
              ),
            ),
            SizedBox(height: 20.h),
            GestureDetector(
              onTap: () => requirePremiumGuard(context, ref),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.br),
                  gradient: LinearGradient(
                    colors: [kPrimaryColor, kDarkBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Text(
                  'Unlock deeper prep',
                  style: AppTypography.textMdBold.copyWith(
                    color: kBlackColor,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
