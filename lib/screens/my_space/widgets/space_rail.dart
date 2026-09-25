import 'dart:math' as math;

import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show discoveryGridCardWidth;
import 'package:chessever2/screens/my_space/widgets/space_player_strip.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Every My Space group but Smart events is one sideways rail: a lazy list
// that starts on the page gutter, runs to the screen edge (or fades out at
// the edge of a page column narrower than the screen), always shows the
// next item peeking while more is to come, and asks for the next page as the
// reader nears its end.

/// How many things a rail loads at a time.
const int kSpaceRailPage = 10;

/// How many faces the Players rail loads at a time: faces are narrow.
const int kSpacePlayersRailPage = 16;

/// How close to its end (in item widths) a rail asks for its next page.
const double kSpaceRailLoadAhead = 1.5;

/// The share of the next item a rail always shows at its edge.
const double kSpaceRailPeek = 1 / 3;

/// How much of its width an item gives up at most so that a rail's items,
/// all of them, stand whole between its gutters rather than end on a peek
/// of nothing (two grid cards on a small phone).
const double kSpaceRailFitWhole = 0.9;

/// The room a rail keeps over and under its cards, for their shadow.
const double kSpaceRailAir = 10;

/// The most a rail asks the next item to show, in points: a third of a
/// narrow card (a grid card, a face), but no more than this of a wide one.
/// Shrinking an event card or a list row to show a third of the next cuts
/// its own lines short ("Se…" for the dates), while an edge this wide of
/// the next card already reads as more to come, never as a sliver.
const double kSpaceRailPeekMax = 48;

/// The widest a wide rail card (a database row, a game in list or board
/// view) stands, in logical pixels: a phone's card, so a tablet's rail
/// shows more cards rather than one stretched across it. Where two of these
/// and a peek do not fit, the rail narrows them to the widest that do
/// (about 460 on a 12.9" iPad in portrait).
const double kSpaceRailWideMax = 520;

/// The widest an event card stands in the Events rail: wide enough on a
/// tablet for the card's one line of dates, cycle and rating to show the
/// whole of the dates ("Sep 20 - 2 Oct, 2026"). The rail never narrows it
/// to fit one more card on the screen (the next shows more of itself
/// instead), so the dates are never cut to make room.
const double kSpaceRailEventWideMax = 580;

/// What kind of item a rail slot holds, which sets its width and the height
/// it is measured under.
enum SpaceRailSlot {
  /// A card the page's width suits: an event, a database or link row, and
  /// a game or line in list or board view.
  wide,

  /// A game or a saved line, as the viewer's games view draws it.
  game,

  /// A face of the Players group.
  face,

  /// Several cards standing as one item: a live event's card over its
  /// boards, or event cards stacked in a column. Its width is its own
  /// ([SpaceRailItem.widthFor]).
  group,
}

/// The width of one of [count] items [natural] wide in a rail that starts
/// [gutter] in and runs [viewport] wide with [gap] between items, so the
/// rail always ends on part of an item: whole items, then an edge of the
/// next at least [kSpaceRailPeek] of it (at most [kSpaceRailPeekMax]) and at
/// most two thirds of it. Where the natural width would leave less (a
/// sliver) the items give up just enough of their width to show that edge;
/// where it would leave more (almost a whole item) one more item stands
/// whole and the items narrow to fit it, unless [addWhole] is false (the
/// items keep their width and the next shows more of itself). Null when
/// the natural width already does, or [count] items fit whole (or [count]
/// items, a little narrower, fit whole: that width).
double? spaceRailPeekWidth({
  required double viewport,
  required double gutter,
  required double gap,
  required double natural,
  int? count,
  bool addWhole = true,
}) {
  final span = viewport - gutter;
  if (natural <= 0 || span <= 0) return null;
  if (count != null) {
    // Every item fits whole: nothing to peek at. Where they nearly do, they
    // give up the little it takes to stand gutter to gutter.
    final fit = (span - gutter - (count - 1) * gap) / count;
    if (fit >= natural) return null;
    if (fit >= natural * kSpaceRailFitWhole) return fit;
  }
  var whole = math.max(1, ((span + gap) / (natural + gap)).floor());
  final rest = span - whole * (natural + gap);
  final least = math.min(natural * kSpaceRailPeek, kSpaceRailPeekMax);
  if (rest >= least && rest <= natural * (1 - kSpaceRailPeek)) return null;
  if (rest > natural * (1 - kSpaceRailPeek)) {
    if (!addWhole) return null;
    whole++;
  }
  final width = (span - whole * gap - least) / whole;
  return width > 0 ? width : null;
}

/// The widths of a rail's slots in a [viewport] wide rail starting [gutter]
/// in, for the viewer's games view [mode].
///
/// Every kind of card stands at its natural width (a wide card at the
/// share of the page [kSpaceRailWideMax] allows, a grid card at the width
/// the grid gives it elsewhere, [discoveryGridCardWidth]) unless that would
/// end the rail on a sliver of the next card, or on nothing at all while
/// more are to come: then the cards give up just enough width to show a
/// real part of the next ([spaceRailPeekWidth]), since the peek is what
/// tells the reader the row scrolls. On a phone that is two grid cards and
/// an edge of the third, a little narrower than Discovery's grid, which
/// fills the screen with two. A kind of card whose items all fit whole
/// ([wideCount], [gameCount] while nothing more is to come) keeps its
/// natural width: there is nothing to peek at.
@immutable
class SpaceRailMetrics {
  const SpaceRailMetrics({
    required this.wide,
    required this.game,
    required this.face,
    required this.gap,
    required this.gridGames,
    this.mode = GamesListViewMode.chessBoardGrid,
    this.boardInset = 0,
  });

  factory SpaceRailMetrics.of(
    BuildContext context, {
    required double viewport,
    required double gutter,
    required GamesListViewMode mode,
    int? faces,
    bool lone = false,
    int? wideCount,
    int? gameCount,
    double wideMax = kSpaceRailWideMax,
    bool wideNarrows = true,
  }) {
    final gap = 12.sp;
    final content = math.max(0.0, viewport - 2 * gutter);
    double peeking(double natural, int? count, {bool addWhole = true}) =>
        spaceRailPeekWidth(
          viewport: viewport,
          gutter: gutter,
          gap: gap,
          natural: natural,
          count: count,
          addWhole: addWhole,
        ) ??
        natural;
    // A phone's card, however wide the screen: on a tablet the rail shows
    // more cards rather than one stretched across it.
    final wideNatural = math.min(content * 0.86, wideMax);
    // A rail of one card has nothing to peek at: it takes the whole line.
    final wide = lone
        ? math.min(content, wideMax)
        : peeking(wideNatural, wideCount, addWhole: wideNarrows);
    final grid = mode == GamesListViewMode.chessBoardGrid;
    final game = grid
        ? (lone
              ? discoveryGridCardWidth(context)
              : peeking(discoveryGridCardWidth(context), gameCount))
        : wide;
    final face =
        SpacePlayerStrip.peekWidth(
          available: viewport,
          padding: gutter,
          count: faces ?? 1000,
        ) ??
        SpacePlayerStrip.itemWidth;
    return SpaceRailMetrics(
      wide: wide,
      game: game,
      face: face,
      gap: gap,
      gridGames: grid,
      mode: mode,
      boardInset: mode == GamesListViewMode.chessBoard ? 24.sp : 0,
    );
  }

  /// The viewer's games view the widths were taken for.
  final GamesListViewMode mode;

  final double wide;
  final double game;
  final double face;
  final double gap;

  /// The full board card's own side inset (`gameBoardCardPadding`): in a
  /// rail the card hangs it past its slot, so the board lines up with the
  /// gutter and the gap between cards is the rail's own.
  final double boardInset;

  /// Games stand as grid cards, which on a phone size themselves from the
  /// screen: the rail hands them a screen that makes them [game] wide.
  final bool gridGames;

  /// Between two faces, the Players rail keeps the strip's own gap; between
  /// anything else, [gap].
  double gapBefore(SpaceRailSlot slot, SpaceRailSlot previous) =>
      slot == SpaceRailSlot.face && previous == SpaceRailSlot.face
      ? SpacePlayerStrip.gap
      : gap;

  double widthOf(SpaceRailSlot slot) => switch (slot) {
    SpaceRailSlot.wide || SpaceRailSlot.group => wide,
    SpaceRailSlot.game => game,
    SpaceRailSlot.face => face,
  };

  /// A slot's height before one of its items has laid out: the cards' own
  /// geometry, close enough that the first measured frame barely moves.
  /// [labelled] games carry a label line over them; a group is an event
  /// card over labelled games.
  double estimate(SpaceRailSlot slot, {bool labelled = false}) {
    final label = labelled ? 16.0 + 8.w : 0.0;
    switch (slot) {
      case SpaceRailSlot.wide:
        return 108.w * 4 / 5 + 12.sp;
      case SpaceRailSlot.face:
        return 4.w + SpacePlayerStrip.face + 8.w + 17 + 1.w + 15 + 4.w;
      case SpaceRailSlot.game:
        final w = game;
        return label +
            switch (mode) {
              GamesListViewMode.chessBoardGrid =>
                20.h + 4.h + (w - 10.w) + 4.h + 20.h,
              GamesListViewMode.gamesCard => 60.h + 24.h,
              GamesListViewMode.chessBoard =>
                2 * 14.0 + 12.h + (w - 48.sp - 20.w) + 8.sp,
            };
      case SpaceRailSlot.group:
        return estimate(SpaceRailSlot.wide) +
            gap +
            estimate(SpaceRailSlot.game, labelled: true);
    }
  }
}

/// One item of a rail: what it is and how to build it at its width. Built
/// only when it scrolls near the viewport.
@immutable
class SpaceRailItem {
  const SpaceRailItem({
    required this.id,
    required this.slot,
    required this.builder,
    this.measured = true,
    this.centered = false,
    this.widthFor,
    this.gameSlots = 0,
  });

  /// Stable across rebuilds, so an item keeps its state as pages land.
  final String id;
  final SpaceRailSlot slot;
  final Widget Function(BuildContext context, double width) builder;

  /// The item's own width from the rail's widths, for a [SpaceRailSlot.group]
  /// (an event and its boards); the slot's width when null.
  final double Function(SpaceRailMetrics metrics)? widthFor;

  /// How many games a group holds, counted with the rail's games when the
  /// rail decides whether they all fit whole.
  final int gameSlots;

  /// The item's width in a rail of [metrics].
  double widthIn(SpaceRailMetrics metrics) =>
      widthFor?.call(metrics) ?? metrics.widthOf(slot);

  /// Whether the item's height sets its slot's height (placeholders and a
  /// retry take the rail's height instead).
  final bool measured;

  /// Whether the item sits in the middle of a taller rail rather than at
  /// its top (a small marker among bigger cards).
  final bool centered;
}

/// A sideways rail of [items] on the page gutter, lazily built
/// ([ListView.builder]), ending on part of an item while more is to come.
/// Items stand in one row with their tops aligned; the row is as tall as its
/// tallest kind of item, measured as they lay out (estimated from the cards'
/// geometry until then). A [SpaceRailSlot.group] item lays several cards out
/// itself, reading the rail's widths from [SpaceRailScope] (its games in
/// [SpaceRailGameSlot]s, a leading card in a [SpaceRailStickyLead]).
///
/// Paging: while [hasMore], the rail calls [onLoadMore] once it scrolls to
/// within [kSpaceRailLoadAhead] item widths of its end, and shows one small
/// skeleton card at the end while [loading] (or while more is to come).
/// The scroll offset is kept per [storageId] across rebuilds.
class SpaceRail extends ConsumerStatefulWidget {
  const SpaceRail({
    super.key,
    required this.storageId,
    required this.items,
    required this.gutter,
    this.labelledGames = false,
    this.hasMore = false,
    this.loading = false,
    this.onLoadMore,
    this.faces,
    this.trailingSlot,
    this.airTop = kSpaceRailAir,
    this.wideMax = kSpaceRailWideMax,
    this.wideNarrows = true,
  });

  final String storageId;
  final List<SpaceRailItem> items;
  final double gutter;

  /// Whether the rail's games carry a label line over them.
  final bool labelledGames;
  final bool hasMore;
  final bool loading;
  final VoidCallback? onLoadMore;

  /// How many faces the rail holds (sizes faces to end on a half face).
  final int? faces;

  /// The slot the trailing skeleton takes; the last item's when null.
  final SpaceRailSlot? trailingSlot;

  /// The widest a wide card stands ([kSpaceRailWideMax]).
  final double wideMax;

  /// Whether wide cards narrow to fit one more whole card on the screen
  /// ([spaceRailPeekWidth]'s addWhole); they always narrow to avoid a
  /// sliver.
  final bool wideNarrows;

  /// The room over the cards (for their shadow in light mode). A rail
  /// standing right under another one of its group passes 0, so the pair
  /// reads as one group rather than two.
  final double airTop;

  @override
  ConsumerState<SpaceRail> createState() => _SpaceRailState();
}

class _SpaceRailState extends ConsumerState<SpaceRail> {
  final _controller = ScrollController();

  /// Each item's size as it last laid out, by item id, for the current
  /// games view and screen. A slot is as tall as the tallest of the items
  /// the rail holds now at the slot's current width, so it shrinks back when
  /// its tallest item leaves or its cards narrow (a lone card taking the
  /// whole line gets company, and a board card's height follows its width).
  final Map<String, ({SpaceRailSlot slot, Size size})> _measured = {};
  Object? _layoutKey;

  /// Bumped with every new layout, so each item reports its size afresh.
  int _generation = 0;

  /// The item count the last page request was made at, so one approach to
  /// the end asks once.
  int? _askedAt;

  double _lastWidth = 0;

  /// What the rail holds after its last real item: the trailing skeleton
  /// and its gap, and the gutter.
  double _tail = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_check);
    // A first page too short to fill the rail asks for the next at once.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(SpaceRail old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length ||
        old.hasMore != widget.hasMore ||
        old.loading != widget.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Asks for the next page once the rail's last real item is within
  /// [kSpaceRailLoadAhead] item widths of the rail's edge (or its items do
  /// not fill it). The trailing skeleton and the gutter after the last item
  /// do not count towards that distance.
  void _check() {
    if (!mounted || !widget.hasMore || widget.loading) return;
    final more = widget.onLoadMore;
    if (more == null || !_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions) return;
    if (position.extentAfter - _tail > kSpaceRailLoadAhead * _lastWidth) {
      return;
    }
    if (_askedAt == widget.items.length) return;
    _askedAt = widget.items.length;
    more();
  }

  void _onMeasured(String id, SpaceRailSlot slot, Size size) {
    if (!mounted) return;
    final known = _measured[id];
    if (known != null &&
        known.slot == slot &&
        (size.width - known.size.width).abs() < 0.5 &&
        (size.height - known.size.height).abs() < 0.5) {
      return;
    }
    setState(() => _measured[id] = (slot: slot, size: size));
  }

  /// The tallest item of [slot] among [items] measured at its current
  /// width in [metrics] (a board card [SpaceRailMetrics.boardInset] wider
  /// each side), if one has laid out.
  double? _tallest(
    SpaceRailSlot slot,
    List<SpaceRailItem> items,
    SpaceRailMetrics metrics,
  ) {
    double? tallest;
    for (final item in items) {
      if (!item.measured || item.slot != slot) continue;
      final known = _measured[item.id];
      if (known == null || known.slot != slot) continue;
      final width = item.widthIn(metrics);
      final laid = slot == SpaceRailSlot.game
          ? width + 2 * metrics.boardInset
          : width;
      if ((known.size.width - laid).abs() >= 0.5) continue;
      final height = known.size.height;
      if (tallest == null || height > tallest) tallest = height;
    }
    return tallest;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(gamesListViewModeProvider);
    final items = widget.items;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        // A page column narrower than the screen (a tablet held
        // landscape): the rail fades out across its trailing gutter, so
        // the next item's edge is measured to where the fade begins.
        final inset =
            widget.gutter > 0 &&
            viewport < MediaQuery.sizeOf(context).width - 1;
        final complete = !widget.hasMore && !widget.loading;
        int? countOf(SpaceRailSlot slot) {
          if (!complete) return null;
          var count = 0;
          for (final i in items) {
            if (i.slot == slot) {
              count++;
            } else if (i.slot == SpaceRailSlot.group) {
              // A group leads with one wide card and holds its games.
              count += slot == SpaceRailSlot.wide ? 1 : 0;
              count += slot == SpaceRailSlot.game ? i.gameSlots : 0;
            }
          }
          return count;
        }

        final metrics = SpaceRailMetrics.of(
          context,
          wideMax: widget.wideMax,
          wideNarrows: widget.wideNarrows,
          viewport: inset ? viewport - widget.gutter : viewport,
          gutter: widget.gutter,
          mode: mode,
          faces: widget.faces,
          // A group has its own games to peek at.
          lone:
              items.length == 1 &&
              complete &&
              items.single.slot != SpaceRailSlot.group,
          wideCount: countOf(SpaceRailSlot.wide),
          gameCount: countOf(SpaceRailSlot.game),
        );
        // A new games view or screen is a new layout: measure afresh. (A
        // card width that changes within one, as a lone card gets company,
        // is told apart by the width each size was measured at.)
        final layoutKey = (mode, viewport, MediaQuery.textScalerOf(context));
        if (layoutKey != _layoutKey) {
          _layoutKey = layoutKey;
          _measured.clear();
          _generation++;
        }
        final slots = {for (final i in items) i.slot};
        final trailing = widget.loading || widget.hasMore;
        final trailSlot =
            widget.trailingSlot ??
            (items.isEmpty ? SpaceRailSlot.wide : items.last.slot);
        if (trailing) slots.add(trailSlot);
        final height = slots.isEmpty
            ? 0.0
            : slots
                  .map(
                    (s) =>
                        _tallest(s, items, metrics) ??
                        metrics.estimate(s, labelled: widget.labelledGames),
                  )
                  .reduce(math.max);
        _lastWidth = items.isEmpty ? metrics.wide : items.last.widthIn(metrics);
        _tail =
            widget.gutter +
            (trailing
                ? metrics.widthOf(trailSlot) +
                      (items.isEmpty
                          ? 0
                          : metrics.gapBefore(trailSlot, items.last.slot))
                : 0);
        // Room over and under the cards for their own shadow (paper).
        const air = kSpaceRailAir;
        final count = items.length + (trailing ? 1 : 0);

        // Built with the item's own context, under [SpaceRailScope].
        Widget sized(BuildContext context, SpaceRailItem item, double width) {
          Widget child = item.builder(context, width);
          if (item.slot == SpaceRailSlot.game &&
              metrics.gridGames &&
              ResponsiveHelper.isPhone) {
            // The grid card takes its width from the screen: hand it a
            // screen that makes it exactly its slot.
            final media = MediaQuery.of(context);
            child = MediaQuery(
              data: media.copyWith(
                size: Size(2 * (width + 24.sp), media.size.height),
              ),
              child: child,
            );
          }
          if (item.measured) {
            child = _SizeProbe(
              generation: _generation,
              onSize: (size) => _onMeasured(item.id, item.slot, size),
              child: child,
            );
          }
          final bleed = item.slot == SpaceRailSlot.game && item.measured
              ? metrics.boardInset
              : 0.0;
          return SizedBox(
            width: width,
            height: height,
            child: OverflowBox(
              alignment: item.centered ? Alignment.center : Alignment.topCenter,
              minWidth: width + 2 * bleed,
              maxWidth: width + 2 * bleed,
              minHeight: 0,
              maxHeight: item.measured ? double.infinity : height,
              child: child,
            ),
          );
        }

        final Widget rail = SizedBox(
          height: height + widget.airTop + air,
          child: SpaceRailScope(
            metrics: metrics,
            gutter: widget.gutter,
            viewport: viewport,
            child: ListView.builder(
            key: PageStorageKey<String>('space_rail_${widget.storageId}'),
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              widget.gutter,
              widget.airTop,
              widget.gutter,
              air,
            ),
            itemCount: count,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final at = items.indexWhere((i) => i.id == key.value);
              return at < 0 ? null : at;
            },
            itemBuilder: (context, index) {
              final gap = index == 0
                  ? 0.0
                  : metrics.gapBefore(
                      index < items.length ? items[index].slot : trailSlot,
                      items[index - 1].slot,
                    );
              if (index >= items.length) {
                return Padding(
                  key: const ValueKey<String>('space_rail_more'),
                  padding: EdgeInsets.only(left: gap),
                  child: SpaceRailSkeleton(
                    width: metrics.widthOf(trailSlot),
                    height: height,
                    round: trailSlot == SpaceRailSlot.face,
                  ),
                );
              }
              final item = items[index];
              return Padding(
                key: ValueKey<String>(item.id),
                padding: EdgeInsets.only(left: gap),
                child: sized(context, item, item.widthIn(metrics)),
              );
            },
            ),
          ),
        );
        // A rail runs to the screen's edge. Where the page is a column
        // narrower than the screen (a tablet held landscape), it can only
        // run to the column's edge: there the cards fade out across the
        // gutter rather than stop on a hard line in the page's margin, and
        // the fade starts where the headers' See all ends.
        if (!inset) return rail;
        final edge = (widget.gutter / viewport).clamp(0.0, 0.5);
        return ShaderMask(
          key: const ValueKey<String>('space_rail_edge_fade'),
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: const [
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000),
            ],
            stops: [0, edge, 1 - edge, 1],
          ).createShader(bounds),
          child: rail,
        );
      },
    );
  }
}

/// A rail slot while its thing loads: a quiet plate of the slot's size (a
/// face's circle for a face).
class SpaceRailSkeleton extends StatelessWidget {
  const SpaceRailSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.round = false,
  });

  final double width;
  final double height;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.surfaceRecessed;
    final Widget plate = round
        ? Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: 4.w),
              child: SizedBox.square(
                dimension: SpacePlayerStrip.face,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
                ),
              ),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(8.br),
            ),
          );
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: SkeletonWidget(
          ignoreContainers: true,
          child: SizedBox(width: width, height: height, child: plate),
        ),
      ),
    );
  }
}

/// Reports its child's size after each layout that changes it, and once
/// more whenever [generation] moves on (the rail measuring afresh).
class _SizeProbe extends SingleChildRenderObjectWidget {
  const _SizeProbe({
    required this.generation,
    required this.onSize,
    super.child,
  });

  final int generation;
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeProbe(onSize, generation);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeProbe object) {
    object
      ..onSize = onSize
      ..generation = generation;
  }
}

class _RenderSizeProbe extends RenderProxyBox {
  _RenderSizeProbe(this.onSize, this._generation);

  ValueChanged<Size> onSize;
  Size? _reported;

  int get generation => _generation;
  int _generation;
  set generation(int value) {
    if (value == _generation) return;
    _generation = value;
    _reported = null;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    final laid = size;
    final last = _reported;
    if (last != null &&
        (laid.width - last.width).abs() < 0.5 &&
        (laid.height - last.height).abs() < 0.5) {
      return;
    }
    _reported = laid;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(laid));
  }
}

/// The widths a rail [viewport] wide on [gutter] gives its items, as
/// [SpaceRail] takes them (a page column narrower than the screen measured
/// to where its fade begins), for a host that arranges its items by their
/// size before handing them over.
SpaceRailMetrics spaceRailMetricsFor(
  BuildContext context, {
  required double viewport,
  required double gutter,
  required GamesListViewMode mode,
  double wideMax = kSpaceRailWideMax,
  bool wideNarrows = true,
}) {
  final inset = gutter > 0 && viewport < MediaQuery.sizeOf(context).width - 1;
  return SpaceRailMetrics.of(
    context,
    viewport: inset ? viewport - gutter : viewport,
    gutter: gutter,
    mode: mode,
    wideMax: wideMax,
    wideNarrows: wideNarrows,
  );
}

/// What the items of a rail can read of the rail they stand in: its widths
/// and its gutter.
class SpaceRailScope extends InheritedWidget {
  const SpaceRailScope({
    super.key,
    required this.metrics,
    required this.gutter,
    required this.viewport,
    required super.child,
  });

  final SpaceRailMetrics metrics;
  final double gutter;

  /// The rail's own width, gutters included.
  final double viewport;

  /// The width between the rail's gutters.
  double get content => math.max(0.0, viewport - 2 * gutter);

  static SpaceRailScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SpaceRailScope>();

  @override
  bool updateShouldNotify(SpaceRailScope old) =>
      old.gutter != gutter ||
      old.viewport != viewport ||
      old.metrics.wide != metrics.wide ||
      old.metrics.game != metrics.game ||
      old.metrics.gap != metrics.gap ||
      old.metrics.mode != metrics.mode ||
      old.metrics.boardInset != metrics.boardInset;
}

/// One game card inside a rail's group, [width] wide: laid out the way the
/// rail lays out a game of its own (a phone's grid card handed a screen
/// that makes it exactly [width], a full board card hanging its own side
/// inset past the slot), and as tall as the card is.
class SpaceRailGameSlot extends StatelessWidget {
  const SpaceRailGameSlot({
    super.key,
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final metrics = SpaceRailScope.maybeOf(context)?.metrics;
    var card = child;
    if (metrics != null && metrics.gridGames && ResponsiveHelper.isPhone) {
      final media = MediaQuery.of(context);
      card = MediaQuery(
        data: media.copyWith(
          size: Size(2 * (width + 24.sp), media.size.height),
        ),
        child: card,
      );
    }
    final bleed = metrics?.boardInset ?? 0;
    return SizedBox(
      width: width,
      child: OverflowBox(
        alignment: Alignment.topCenter,
        fit: OverflowBoxFit.deferToChild,
        minWidth: width + 2 * bleed,
        maxWidth: width + 2 * bleed,
        child: card,
      ),
    );
  }
}

/// The card that leads a group ([width] wide, at the group's top left)
/// and stays in view while the group scrolls under it: as the group's
/// leading edge passes the rail's gutter, the card holds at the gutter,
/// until the group's end carries it off. An event's card so stays over its
/// boards however far they are scrolled, and the next event's card takes
/// its place with the next event's boards.
///
/// The card moves at paint time, on its own layer, as the rail scrolls:
/// nothing is laid out or built again.
class SpaceRailStickyLead extends StatelessWidget {
  const SpaceRailStickyLead({
    super.key,
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.maybeOf(
      context,
      axis: Axis.horizontal,
    )?.position;
    final gutter = SpaceRailScope.maybeOf(context)?.gutter ?? 0;
    return _StickyLead(
      position: position,
      gutter: gutter,
      width: width,
      child: RepaintBoundary(child: child),
    );
  }
}

class _StickyLead extends SingleChildRenderObjectWidget {
  const _StickyLead({
    required this.position,
    required this.gutter,
    required this.width,
    super.child,
  });

  final ScrollPosition? position;
  final double gutter;
  final double width;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStickyLead(position: position, gutter: gutter, width: width);

  @override
  void updateRenderObject(BuildContext context, _RenderStickyLead object) {
    object
      ..position = position
      ..gutter = gutter
      ..width = width;
  }
}

class _RenderStickyLead extends RenderProxyBox {
  _RenderStickyLead({
    ScrollPosition? position,
    required double gutter,
    required double width,
  }) {
    _position = position;
    _gutter = gutter;
    _width = width;
  }

  ScrollPosition? _position;
  set position(ScrollPosition? value) {
    if (identical(value, _position)) return;
    if (attached) _position?.removeListener(markNeedsPaint);
    _position = value;
    if (attached) _position?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  late double _gutter;
  set gutter(double value) {
    if (value == _gutter) return;
    _gutter = value;
    markNeedsPaint();
  }

  late double _width;
  set width(double value) {
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _position?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    final box = child;
    if (box == null) {
      size = constraints.smallest;
      return;
    }
    final width = _width.clamp(constraints.minWidth, constraints.maxWidth);
    box.layout(
      constraints.copyWith(minWidth: width, maxWidth: width),
      parentUsesSize: true,
    );
    size = constraints.constrain(Size(constraints.maxWidth, box.size.height));
  }

  /// How far the card has moved in from the group's leading edge: as far
  /// as the edge has passed the gutter, never past the group's end.
  double get _shift {
    final box = child;
    if (box == null || !hasSize || !box.hasSize) return 0;
    final room = size.width - box.size.width;
    if (room <= 0) return 0;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is! RenderBox) return 0;
    final left = getTransformTo(viewport).getTranslation().x;
    return (_gutter - left).clamp(0.0, room);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final box = child;
    if (box != null) context.paintChild(box, offset + Offset(_shift, 0));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final box = child;
    if (box == null) return false;
    return result.addWithPaintOffset(
      offset: Offset(_shift, 0),
      position: position,
      hitTest: (result, transformed) =>
          box.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_shift, 0, 0, 1);
  }
}

/// How many pages each My Space rail has asked for this session, by rail
/// id. Kept outside the rail, so a group scrolled out and back (or rebuilt
/// around a new pin) keeps its pages and the rail's kept offset still lands
/// on loaded items, and so one group can read another's pages (the Players
/// rail leaves out the boards the Events rail's loaded pages already draw).
final spaceRailPagesProvider = StateProvider.family<int, String>(
  (ref, id) => 1,
);

/// Paging for a rail's host: how many pages its rail [pagingId] has asked
/// for ([spaceRailPagesProvider]), and asking for one more.
mixin SpaceRailPaging<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String get pagingId;

  int get pages => ref.watch(spaceRailPagesProvider(pagingId));

  void loadMore() =>
      ref.read(spaceRailPagesProvider(pagingId).notifier).state++;
}
