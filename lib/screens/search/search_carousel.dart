import 'dart:math' as math;

import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryType, discoveryType;
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/screens/search/search_page_sections.dart'
    show searchCardGap, searchPageGutter;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// The Search tab's rows: each section's cards side by side, the next one
// peeking past the edge, read on a page at a time as the reader nears the
// end, ending in a card that opens the section's own page. The same cards,
// opened in place or on that page, stand in rows down the page
// ([SearchPagedRows]). Neither draws a card of its own: the cards are the
// app's, these only lay them out and say what is still coming.

/// The share of a phone row's width left for the next card to peek in: a
/// tenth, so a card keeps nearly the width it has down a page (its words
/// laid out as they are there) and the next one still shows.
const double searchCarouselPeekShare = 0.1;

/// How wide one card of a row stands across [content] (the width between
/// the gutters): on a phone [phoneColumns] cards in nine tenths of the row
/// ([searchCarouselPeekShare]); on a tablet a grid column's width (at
/// least [tabletMinWidth]), with a quarter of the next card past the edge.
double searchCarouselItemWidth(
  double content, {
  required double tabletMinWidth,
  int phoneColumns = 1,
}) {
  final gap = searchCardGap;
  if (!ResponsiveHelper.isTablet) {
    final columns = math.max(1, phoneColumns);
    return (content + gap) / (columns * (1 + searchCarouselPeekShare)) - gap;
  }
  final columns = ResponsiveHelper.columnsForWidth(
    content,
    minItemWidth: tabletMinWidth,
    spacing: gap,
    maxColumns: 4,
  );
  return (content + gap) / (columns + 0.25) - gap;
}

/// How tall a row of one section's cards stands.
@immutable
class SearchCarouselSizing {
  const SearchCarouselSizing.ghost(
    this.ghost, {
    this.tabletMinWidth = 280,
    this.phoneColumns = 1,
  }) : extent = null,
       bottomRoom = 0;

  const SearchCarouselSizing.fixed(
    this.extent, {
    this.tabletMinWidth = 280,
    this.phoneColumns = 1,
    this.bottomRoom = 0,
  }) : ghost = null;

  /// For cards whose height follows their words: the section's tallest card
  /// (every line its words can take), never painted, laid out at a card's
  /// width. The row is as tall as it, and every card stands that tall, so
  /// the cards of a row line up top and bottom.
  final Widget Function(double width)? ghost;

  /// For cards of a set height: the row's height for cards this wide.
  final double Function(BuildContext context, double width)? extent;

  /// Room under the cards for what a card draws past its own bottom edge
  /// (a news story's stacked sheets).
  final double bottomRoom;

  /// The least width of a card on a tablet.
  final double tabletMinWidth;

  /// Cards side by side on a phone before the next one peeks: 1 for the
  /// row cards drawn across a page, 2 for cards a page sets two to a row
  /// (the News page's).
  final int phoneColumns;
}

/// One section's cards side by side ([searchCarouselItemWidth] each), the
/// row starting and ending on the page's gutter and scrolling under it to
/// the screen's edges.
///
/// It reads on by itself: as the reader nears the end it asks for the
/// next page ([onLoadMore]), whose room is held at the end by a card-sized
/// slot with one quiet spinner, so nothing moves when the page lands. A
/// page that fails ends the row in a quiet retry card ([onRetry]). Once the
/// source is spent the row ends in the See more card, the size of the
/// others, which opens the section's own page ([onSeeMore]). [pending]
/// slots hold the room of cards already on their way (Live now's lookups).
///
/// A fling comes to rest with a card on the gutter. The row is horizontal,
/// so it never moves the bars ([ScrollChromeRegion] reads only vertical
/// lists), and it keeps its place while the tab lives (its
/// [PageStorageKey]).
class SearchCarousel extends StatefulWidget {
  const SearchCarousel({
    super.key,
    required this.section,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    required this.sizing,
    required this.onSeeMore,
    this.pending = 0,
    this.hasMore = false,
    this.loading = false,
    this.failed = false,
    this.onLoadMore,
    this.onRetry,
  });

  /// Names the row's own slots: `search-<section>-pending`,
  /// `search-<section>-retry`, `search-<section>-see-more`.
  final String section;

  /// The section's name, for what a screen reader says of the See more card.
  final String title;
  final int itemCount;

  /// The card at an index, as the section draws it.
  final IndexedWidgetBuilder itemBuilder;
  final SearchCarouselSizing sizing;
  final VoidCallback onSeeMore;
  final int pending;
  final bool hasMore;
  final bool loading;
  final bool failed;
  final VoidCallback? onLoadMore;
  final VoidCallback? onRetry;

  @override
  State<SearchCarousel> createState() => _SearchCarouselState();
}

class _SearchCarouselState extends State<SearchCarousel> {
  late final ScrollController _controller = ScrollController()
    ..addListener(_nearEnd);

  /// One card and the gap after it.
  double _slot = 0;

  /// The row's room before its first card and after its last.
  double _ends = 0;
  bool _checkQueued = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Asks for the next page once fewer than two cards' worth of row are
  /// left past the screen's edge.
  ///
  /// The row's length is counted from its own slots, not read off the
  /// scroll position: a page that lands while the row's end lies past what
  /// is built leaves the position's extent as it was until the row next
  /// lays out, and reading that would ask for page after page while the
  /// row sits still.
  void _nearEnd() {
    final load = widget.onLoadMore;
    if (load == null ||
        !widget.hasMore ||
        widget.loading ||
        widget.failed ||
        widget.pending > 0 ||
        _slot <= 0 ||
        !_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    if (!position.hasPixels || !position.hasViewportDimension) return;
    final slots = widget.itemCount + widget.pending + _tailSlots;
    final after =
        _ends + slots * _slot - position.pixels - position.viewportDimension;
    if (after <= _slot * 2) load();
  }

  /// The slots after the cards: the loading slot, the retry card or See
  /// more, unless pending slots end the row.
  int get _tailSlots => widget.pending == 0 ? 1 : 0;

  /// A row short of the screen (a first page on a tablet) reads on without
  /// a scroll: looked at once a frame has laid it out.
  void _queueCheck() {
    if (_checkQueued) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (mounted) _nearEnd();
    });
  }

  /// The row ends in a page on its way: never once a page has failed,
  /// which ends it in the retry card instead.
  bool get _tailLoading =>
      widget.pending == 0 &&
      !widget.failed &&
      (widget.hasMore || widget.loading);

  Widget _slotAt(BuildContext context, int index) {
    final cards = widget.itemCount;
    if (index < cards) {
      final card = widget.itemBuilder(context, index);
      // A card of a set height stands in the row's height as it is.
      if (widget.sizing.ghost == null) return card;
      // The section's tallest card sets the row; a card a hair taller than
      // that is drawn whole, never squeezed or cut.
      return OverflowBox(
        alignment: AlignmentDirectional.topStart,
        maxHeight: double.infinity,
        child: card,
      );
    }
    final section = widget.section;
    final slot = index - cards;
    if (slot < widget.pending || (slot == widget.pending && _tailLoading)) {
      return SearchLoadingSlot(
        key: slot == 0 ? ValueKey('search-$section-pending') : null,
        spinner: slot == 0,
      );
    }
    if (widget.failed) {
      return SearchRetryCard(
        key: ValueKey('search-$section-retry'),
        onRetry: widget.onRetry,
      );
    }
    return SearchSeeMoreCard(
      key: ValueKey('search-$section-see-more'),
      title: widget.title,
      onTap: widget.onSeeMore,
    );
  }

  @override
  Widget build(BuildContext context) {
    _queueCheck();
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = searchPageGutter;
        final gap = searchCardGap;
        final content = math.max(0.0, constraints.maxWidth - gutter * 2);
        final width = searchCarouselItemWidth(
          content,
          tabletMinWidth: widget.sizing.tabletMinWidth,
          phoneColumns: widget.sizing.phoneColumns,
        );
        _slot = width + gap;
        final end = math.max(0.0, gutter - gap);
        _ends = gutter + end;
        final list = ListView.builder(
          key: PageStorageKey<String>('search-carousel-${widget.section}'),
          controller: _controller,
          scrollDirection: Axis.horizontal,
          // A card's own shadow and lift stay whole above and below the row.
          clipBehavior: Clip.none,
          physics: SearchCarouselPhysics(() => _slot),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsetsDirectional.only(start: gutter, end: end),
          itemExtent: _slot,
          itemCount: widget.itemCount + widget.pending + _tailSlots,
          itemBuilder: (context, index) => Padding(
            padding: EdgeInsetsDirectional.only(end: gap),
            child: _slotAt(context, index),
          ),
        );
        final fixed = widget.sizing.extent;
        if (fixed != null) {
          return SizedBox(
            height: fixed(context, width) + widget.sizing.bottomRoom,
            child: list,
          );
        }
        return Stack(
          children: [
            // The row's height: the tallest card the section draws.
            Row(
              children: [
                SizedBox(width: gutter),
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: Visibility(
                      visible: false,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: SizedBox(
                        width: width,
                        child: widget.sizing.ghost!(width),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned.fill(child: list),
          ],
        );
      },
    );
  }
}

/// A row's fling comes to rest with a card on the gutter: where the fling
/// would have stopped, moved to the nearest card's edge, and at least one
/// card on the way it went. Past either end the platform's own physics
/// bring it back.
class SearchCarouselPhysics extends ScrollPhysics {
  const SearchCarouselPhysics(this._readSlot, {super.parent});

  // Scrollable can keep its existing physics when the card width changes.
  final double Function() _readSlot;

  /// The current width of one card and the gap after it.
  double get slot => _readSlot();

  @override
  SearchCarouselPhysics applyTo(ScrollPhysics? ancestor) =>
      SearchCarouselPhysics(_readSlot, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final slot = this.slot;
    if (slot <= 0 || position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final pixels = position.pixels;
    // Where a free fling would come to rest (the iOS deceleration).
    final rest = FrictionSimulation(0.135, pixels, velocity).finalX;
    var target = (rest / slot).roundToDouble() * slot;
    if (velocity > tolerance.velocity) {
      target = math.max(target, (pixels / slot).floorToDouble() * slot + slot);
    } else if (velocity < -tolerance.velocity) {
      target = math.min(target, (pixels / slot).ceilToDouble() * slot - slot);
    }
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

/// The room of a card still on its way: nothing drawn but, on the first,
/// one quiet spinner in its middle.
class SearchLoadingSlot extends StatelessWidget {
  const SearchLoadingSlot({super.key, this.spinner = true});

  final bool spinner;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.expand(
        child: spinner
            ? const Center(child: SearchQuietSpinner())
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// The app's quiet spinner: small, thin, in the secondary ink.
class SearchQuietSpinner extends StatelessWidget {
  const SearchQuietSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 18.ic,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: context.colors.textSecondary,
      ),
    );
  }
}

/// A card's quiet surface: the cards' own tone and corner, the paper
/// theme's hairline.
class _SlotSurface extends StatelessWidget {
  const _SlotSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border: context.isLightTheme
            ? Border.all(color: colors.divider.withValues(alpha: 0.4))
            : null,
      ),
      child: SizedBox.expand(child: child),
    );
  }
}

/// A card-sized press: the whole slot is the target, going down under the
/// finger as every card does.
class _SlotPress extends StatelessWidget {
  const _SlotPress({
    required this.label,
    required this.hint,
    required this.onTap,
    required this.child,
  });

  final String label;
  final String hint;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return Semantics(
      container: true,
      button: true,
      label: label,
      hint: hint,
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: PressSpring(pressedScale: 0.97, child: child),
      ),
    );
  }
}

/// The last card of a row once its source is spent: See more, the size of
/// the cards before it, opening the section's own page.
class SearchSeeMoreCard extends StatelessWidget {
  const SearchSeeMoreCard({
    super.key,
    required this.title,
    required this.onTap,
  });

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = discoveryType(
      context,
      DiscoveryType.label,
      weight: FontWeight.w600,
    );
    final line = MediaQuery.textScalerOf(context).scale(style.fontSize ?? 13);
    return _SlotPress(
      label: 'See more',
      hint: 'Opens $title',
      onTap: onTap,
      child: _SlotSurface(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'See more',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                SizedBox(width: 6.w),
                SpaceGlyph(
                  SpaceGlyphKind.arrowUpRight,
                  size: line * 0.8,
                  ink: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A page that did not come: a card-sized quiet note, the whole card the
/// way to ask again.
class SearchRetryCard extends StatelessWidget {
  const SearchRetryCard({super.key, required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _SlotPress(
      label: 'Try again',
      hint: "Couldn't load more",
      onTap: onRetry,
      child: _SlotSurface(
        child: Center(child: _RetryWords(onRetry: onRetry)),
      ),
    );
  }
}

class _RetryWords extends StatelessWidget {
  const _RetryWords({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Couldn't load more",
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textSmRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Try again',
            maxLines: 1,
            style: discoveryType(
              context,
              DiscoveryType.label,
              weight: FontWeight.w600,
              color: onRetry == null ? colors.textTertiary : colors.accentText,
            ),
          ),
        ],
      ),
    );
  }
}

/// One section's cards down the page, [columns] to a row, read on a page at
/// a time as the reader nears the last row: the section opened in place on
/// the landing, and the section's own page.
///
/// After the last row: a row's worth of room with one quiet spinner while
/// the next page (or [pending] cards) is on its way, a quiet retry line
/// when a page failed, then [end] (Show less, where the section folds back).
class SearchPagedRows<T> extends StatefulWidget {
  const SearchPagedRows({
    super.key,
    required this.section,
    required this.items,
    required this.columns,
    required this.row,
    this.pending = 0,
    this.hasMore = false,
    this.loading = false,
    this.failed = false,
    this.onLoadMore,
    this.onRetry,
    this.end,
  });

  /// Names the rows' own slots: `search-<section>-rows-pending`,
  /// `search-<section>-rows-retry`.
  final String section;
  final List<T> items;

  /// Cards to a row across the rows' width.
  final int Function(double width) columns;

  /// The row of [items] from [start], [columns] wide, across [width].
  final Widget Function(
    BuildContext context,
    List<T> items,
    int start,
    int columns,
    double width,
  )
  row;
  final int pending;
  final bool hasMore;
  final bool loading;
  final bool failed;
  final VoidCallback? onLoadMore;
  final VoidCallback? onRetry;
  final Widget? end;

  @override
  State<SearchPagedRows<T>> createState() => _SearchPagedRowsState<T>();
}

class _SearchPagedRowsState<T> extends State<SearchPagedRows<T>> {
  bool _asked = false;

  /// The last rows are being built: the next page is asked for after this
  /// frame, once.
  void _nearEnd() {
    if (_asked) return;
    final load = widget.onLoadMore;
    if (load == null ||
        !widget.hasMore ||
        widget.loading ||
        widget.failed ||
        widget.pending > 0) {
      return;
    }
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _asked = false;
      if (!mounted) return;
      if (widget.hasMore &&
          !widget.loading &&
          !widget.failed &&
          widget.pending == 0) {
        widget.onLoadMore?.call();
      }
    });
  }

  Widget _footer(BuildContext context) {
    final gap = searchCardGap;
    final section = widget.section;
    final coming = widget.pending > 0 || widget.hasMore || widget.loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.failed)
          Padding(
            padding: EdgeInsets.only(top: gap),
            child: _RetryLine(
              key: ValueKey('search-$section-rows-retry'),
              onRetry: widget.onRetry,
            ),
          )
        else if (coming)
          SizedBox(
            key: ValueKey('search-$section-rows-pending'),
            height: math.max(56.0, 56.h),
            child: const ExcludeSemantics(
              child: Center(child: SearchQuietSpinner()),
            ),
          ),
        ?widget.end,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = math.max(1, widget.columns(width));
        final rows = (items.length + columns - 1) ~/ columns;
        return SliverList.builder(
          itemCount: rows + 1,
          itemBuilder: (context, index) {
            if (index == rows) return _footer(context);
            if (index >= rows - 2) _nearEnd();
            final start = index * columns;
            return Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : searchCardGap),
              child: widget.row(context, items, start, columns, width),
            );
          },
        );
      },
    );
  }
}

/// [items] from [start] as one row of [columns] equal cards, [cardBuilder]
/// drawing each (with its index in [items]); a short last row keeps its
/// empty slots, so its cards stand where the rows above do. With [extent]
/// every card of the row stands that tall (a grid of image cards).
Widget searchCardRow<T>(
  List<T> items,
  int start,
  int columns, {
  required Widget Function(T item, int index) cardBuilder,
  double? extent,
}) {
  final gap = searchCardGap;
  final row = Row(
    crossAxisAlignment: extent == null
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.stretch,
    children: [
      for (var c = 0; c < columns; c++) ...[
        if (c > 0) SizedBox(width: gap),
        Expanded(
          child: start + c < items.length
              ? cardBuilder(items[start + c], start + c)
              : const SizedBox.shrink(),
        ),
      ],
    ],
  );
  return extent == null ? row : SizedBox(height: extent, child: row);
}

/// A page that did not come, at the end of a section's rows: the words and
/// the way to ask again, a 44pt target.
class _RetryLine extends StatelessWidget {
  const _RetryLine({super.key, required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tap = onRetry;
    return Semantics(
      container: true,
      button: true,
      label: 'Try again',
      hint: "Couldn't load more",
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: PressSpring(
          pressedScale: 0.97,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(44.0, 44.w)),
            child: Center(child: _RetryWords(onRetry: tap)),
          ),
        ),
      ),
    );
  }
}
