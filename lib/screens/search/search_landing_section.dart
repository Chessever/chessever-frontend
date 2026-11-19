import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction, DiscoveryType, discoveryType;
import 'package:chessever2/screens/search/search_carousel.dart';
import 'package:chessever2/screens/search/search_feeds.dart';
import 'package:chessever2/screens/search/search_page_sections.dart'
    show searchHeadingGap, searchPageGutter, searchSectionGap;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/page_spring.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// A landing section's head: its title as a button (the heading's own type,
/// a chevron after it) that opens the section's own page, and at most one
/// action at the far end. On the page's gutter, 44 tall.
class SearchSectionHeading extends StatelessWidget {
  const SearchSectionHeading({
    super.key,
    required this.title,
    required this.onOpen,
    this.buttonKey,
    this.trailing,
  });

  final String title;
  final VoidCallback onOpen;
  final Key? buttonKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final gutter = searchPageGutter;
    final end = trailing;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: math.max(44.0, 44.w)),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: SearchSectionTitleButton(
                  key: buttonKey,
                  title: title,
                  onOpen: onOpen,
                ),
              ),
            ),
            if (end != null) ...[SizedBox(width: 12.w), end],
          ],
        ),
      ),
    );
  }
}

/// A section's title as the way to its page: the words in the section
/// heading's type, a chevron after them in quiet ink, centred on the words'
/// line. A 44pt target that goes down under the finger; heard as "Open
/// <title>", a heading and a button.
class SearchSectionTitleButton extends StatelessWidget {
  const SearchSectionTitleButton({
    super.key,
    required this.title,
    required this.onOpen,
  });

  final String title;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final style = discoveryType(context, DiscoveryType.title);
    final glyph =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 17) * 1.15;
    void open() {
      HapticFeedbackService.navigation();
      onOpen();
    }

    final target = math.max(44.0, 44.w);
    return Semantics(
      container: true,
      header: true,
      button: true,
      label: 'Open $title',
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: PressSpring(
          pressedScale: 0.97,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: target, minWidth: target),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                SizedBox(width: 2.w),
                Icon(
                  Icons.chevron_right_rounded,
                  size: glyph,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The control that opens a section in place (See more, its chevron
/// pointing down) or folds it back (Show less, pointing up): the actions'
/// ink, a 44pt target on the gutter.
class SearchSectionToggle extends StatelessWidget {
  const SearchSectionToggle({
    super.key,
    required this.title,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = discoveryType(
      context,
      DiscoveryType.label,
      weight: FontWeight.w600,
      color: colors.accentText,
    );
    final label = expanded ? 'Show less' : 'See more';
    final glyph =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 13) * 1.35;
    final target = math.max(44.0, 44.w);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: searchPageGutter),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          container: true,
          button: true,
          label: label,
          hint: expanded ? 'Folds $title back' : 'Shows all of $title here',
          onTap: onTap,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedbackService.selection();
              onTap();
            },
            child: PressSpring(
              pressedScale: 0.96,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: target,
                  minWidth: target,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, maxLines: 1, style: style),
                    SizedBox(width: 2.w),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: glyph,
                      color: colors.accentText,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The spring a section opens in place and folds back on.
const Motion searchSectionRevealMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 460),
  snapToEnd: true,
);

/// One section of the landing: its head ([SearchSectionHeading], the title
/// opening the section's page through [onOpen]), then its cards.
///
/// Folded, the cards stand in a row ([SearchCarousel]) with See more under
/// it. See more opens the section in place: the same cards down the page
/// ([SearchPagedRows]), read on as the reader nears the end, with Show less
/// at the end (and in the head) to fold it back. Opening grows the section
/// on a spring from the row's height, pushing the sections below down;
/// folding shrinks it back. Folded from far down the open section, the page
/// first springs back to its head (the tabs' spring, as a re-tapped tab's
/// list goes to its top), then the section folds there, where the reader
/// sees it. Under reduced motion all of it is immediate. Which sections are open is kept while
/// the tab lives ([searchExpandedSectionsProvider]).
///
/// Every card is visible from its first frame: the growth only uncovers
/// cards already drawn.
class SearchLandingSection<T> extends ConsumerStatefulWidget {
  const SearchLandingSection({
    super.key,
    required this.id,
    required this.title,
    required this.items,
    required this.card,
    required this.sizing,
    required this.columns,
    required this.onOpen,
    this.row,
    this.pending = 0,
    this.hasMore = false,
    this.loading = false,
    this.failed = false,
    this.onLoadMore,
    this.onRetry,
  });

  /// Names the section's keys (`search-<id>-open`, `search-<id>-expand`) and
  /// its place in [searchExpandedSectionsProvider].
  final String id;
  final String title;
  final List<T> items;

  /// The card of [items] at an index. [inRow] is true in the row, false
  /// down the page.
  final Widget Function(BuildContext context, T item, int index, bool inRow)
  card;
  final SearchCarouselSizing sizing;

  /// Cards to a row down the page, across [width].
  final int Function(double width) columns;

  /// A row down the page, when the section lays its own out; else
  /// [searchCardRow] of [card].
  final Widget Function(
    BuildContext context,
    List<T> items,
    int start,
    int columns,
    double width,
  )?
  row;
  final VoidCallback onOpen;
  final int pending;
  final bool hasMore;
  final bool loading;
  final bool failed;
  final VoidCallback? onLoadMore;
  final VoidCallback? onRetry;

  @override
  ConsumerState<SearchLandingSection<T>> createState() =>
      _SearchLandingSectionState<T>();
}

class _SearchLandingSectionState<T>
    extends ConsumerState<SearchLandingSection<T>> {
  final _headKey = GlobalKey();
  final _rowKey = GlobalKey();

  /// The folded section's height under its head, by section, as last
  /// measured: a section built open (kept open across a search) folds to
  /// the height its row had.
  static final _foldedHeights = <String, double>{};

  /// The folded section's height under its head: where opening starts and
  /// folding ends.
  double get _folded => _foldedHeights[widget.id] ?? 0;

  /// The open section's height under its head, as last laid out.
  double _open = 0;

  /// Mid-growth or mid-fold: the section shows [_folded] plus this share
  /// of [_span].
  bool _moving = false;
  bool _opening = false;
  double _span = 0;

  /// The page is springing back to the head before a fold: another Show
  /// less waits for it.
  bool _revealing = false;

  bool get _reduce => MediaQuery.disableAnimationsOf(context);

  void _setExpanded(bool expanded) {
    final notifier = ref.read(searchExpandedSectionsProvider.notifier);
    final sections = {...notifier.state};
    expanded ? sections.add(widget.id) : sections.remove(widget.id);
    notifier.state = sections;
  }

  double get _viewport => MediaQuery.sizeOf(context).height;

  void _expand() {
    final row = _rowKey.currentContext?.findRenderObject();
    if (row is RenderBox && row.hasSize) {
      _foldedHeights[widget.id] = row.size.height;
    }
    _setExpanded(true);
    if (_reduce) return;
    // Laid out once at the row's height, so the growth knows how far the
    // open section reaches; then it grows on the spring.
    setState(() {
      _moving = true;
      _opening = false;
      _span = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_moving) return;
      setState(() {
        _span = (_open - _folded).clamp(0.0, _viewport);
        _opening = true;
      });
    });
  }

  bool get _expanded =>
      ref.read(searchExpandedSectionsProvider).contains(widget.id);

  Future<void> _collapse() async {
    // Already on its way back (springing to the head, or folding).
    if (_revealing || (_moving && !_opening)) return;
    final above = _headAbove();
    if (_reduce) {
      above?.position.jumpTo(above.top);
      _setExpanded(false);
      return;
    }
    final span = (_open - _folded).clamp(0.0, _viewport);
    if (above != null) {
      // The fold only shortens the section from the bottom of its first
      // screen: begun with the page far down it, it would pull the page
      // out from under the reader. So the page springs back to the head
      // first (the tabs' spring), and the fold begins as soon as all it
      // shortens lies past the foot of the screen, while the page settles.
      final position = above.position;
      final lead = math.max(
        0.0,
        above.head + _folded + span - position.viewportDimension,
      );
      final near = Completer<void>();
      void check() {
        if (!near.isCompleted && position.pixels - above.top <= lead + 0.5) {
          near.complete();
        }
      }

      _revealing = true;
      position.addListener(check);
      final spring = SpringCurve.of(PageSpring.motion);
      try {
        await Future.any([
          near.future,
          position.animateTo(
            above.top,
            duration: spring.duration,
            curve: spring,
          ),
        ]);
      } finally {
        position.removeListener(check);
        _revealing = false;
      }
      if (!mounted || !_expanded) return;
      // A finger that stopped the spring on the way: the rest of the way
      // at once, so the fold still happens in view.
      final still = _headAbove();
      if (still != null && still.position.pixels - still.top > lead + 0.5) {
        still.position.jumpTo(still.top);
      }
    }
    setState(() {
      _span = span;
      _moving = true;
      _opening = false;
    });
  }

  /// Where the page has to be for the head to sit at its top, with the
  /// page's scroll position and the head's height, when the head has
  /// scrolled away above; null while it is in view.
  ({ScrollPosition position, double top, double head})? _headAbove() {
    final head = _headKey.currentContext;
    final box = head?.findRenderObject();
    if (head == null || box is! RenderBox || !box.attached) return null;
    final position = Scrollable.maybeOf(head)?.position;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (position == null || viewport == null) return null;
    final top = viewport
        .getOffsetToReveal(box, 0)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (top >= position.pixels - 0.5) return null;
    return (position: position, top: top, head: box.size.height);
  }

  void _settled(AnimationStatus status) {
    if (status.isAnimating || !_moving) return;
    if (_opening) {
      setState(() => _moving = false);
    } else if (_span > 0 || _open <= _folded) {
      setState(() => _moving = false);
      _setExpanded(false);
    }
  }

  Widget _rows(List<T> items) {
    final widget = this.widget;
    final rowBuilder =
        widget.row ??
        (context, items, start, columns, width) => searchCardRow<T>(
          items,
          start,
          columns,
          cardBuilder: (item, index) =>
              widget.card(context, item, index, false),
        );
    return SearchPagedRows<T>(
      section: widget.id,
      items: items,
      columns: widget.columns,
      row: rowBuilder,
      pending: widget.pending,
      hasMore: widget.hasMore,
      loading: widget.loading,
      failed: widget.failed,
      onLoadMore: widget.onLoadMore,
      onRetry: widget.onRetry,
      end: Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: SearchSectionToggle(
          key: ValueKey('search-${widget.id}-collapse'),
          title: widget.title,
          expanded: true,
          onTap: _collapse,
        ),
      ),
    );
  }

  Widget _carousel(BuildContext context) {
    final widget = this.widget;
    final items = widget.items;
    // Cards on their way count: See more is there before they land, so
    // nothing under the row moves when they do.
    final canExpand = items.length + widget.pending > 1 || widget.hasMore;
    return Column(
      key: _rowKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: searchHeadingGap),
        SearchCarousel(
          section: widget.id,
          title: widget.title,
          itemCount: items.length,
          itemBuilder: (context, index) =>
              widget.card(context, items[index], index, true),
          sizing: widget.sizing,
          onSeeMore: widget.onOpen,
          pending: widget.pending,
          hasMore: widget.hasMore,
          loading: widget.loading,
          failed: widget.failed,
          onLoadMore: widget.onLoadMore,
          onRetry: widget.onRetry,
        ),
        if (canExpand) ...[
          SizedBox(height: 2.h),
          SearchSectionToggle(
            key: ValueKey('search-${widget.id}-expand'),
            title: widget.title,
            expanded: false,
            onTap: _expand,
          ),
          SizedBox(height: math.max(0.0, searchSectionGap - 12.sp)),
        ] else
          SizedBox(height: searchSectionGap),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final expanded = ref.watch(
      searchExpandedSectionsProvider.select((open) => open.contains(widget.id)),
    );
    // Open and at rest, the spring rests open: a section built open (kept
    // open while a search was typed and cleared) folds on the spring from
    // there, as one opened a moment ago does.
    if (expanded && !_moving) _opening = true;
    final head = SliverToBoxAdapter(
      child: SearchSectionHeading(
        key: _headKey,
        buttonKey: ValueKey('search-${widget.id}-open'),
        title: widget.title,
        onOpen: widget.onOpen,
        trailing: expanded
            ? DiscoveryAction(
                key: ValueKey('search-${widget.id}-fold'),
                label: 'Show less',
                semanticsLabel: 'Show less of ${widget.title}',
                onTap: _collapse,
              )
            : null,
      ),
    );
    if (!expanded) {
      return SliverMainAxisGroup(
        slivers: [
          head,
          SliverToBoxAdapter(child: _carousel(context)),
        ],
      );
    }
    final gutter = searchPageGutter;
    final body = SliverPadding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        searchHeadingGap,
        gutter,
        math.max(0.0, searchSectionGap - 12.sp),
      ),
      sliver: _rows(widget.items),
    );
    return SliverMainAxisGroup(
      slivers: [
        head,
        SingleMotionBuilder(
          motion: searchSectionRevealMotion,
          value: _opening ? 1.0 : 0.0,
          active: !_reduce,
          onAnimationStatusChanged: _settled,
          builder: (context, t, child) => _SliverReveal(
            extent: _moving
                ? _folded + _span * t.clamp(0.0, 1.0)
                : double.infinity,
            onExtent: (extent) => _open = extent,
            sliver: child!,
          ),
          child: body,
        ),
      ],
    );
  }
}

/// Shows [sliver] down to [extent] (its whole when shorter, or when
/// [extent] is infinite), the rest uncovered as [extent] grows: the
/// opening section's growth. The cards are laid out and drawn as they are;
/// only what lies past [extent] is held back. Reports the sliver's whole
/// extent to [onExtent] as it lays out.
class _SliverReveal extends SingleChildRenderObjectWidget {
  const _SliverReveal({
    required this.extent,
    required this.onExtent,
    required Widget sliver,
  }) : super(child: sliver);

  final double extent;
  final ValueChanged<double> onExtent;

  @override
  _RenderSliverReveal createRenderObject(BuildContext context) =>
      _RenderSliverReveal(extent, onExtent: onExtent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverReveal renderObject,
  ) {
    renderObject
      ..extent = extent
      ..onExtent = onExtent;
  }
}

class _RenderSliverReveal extends RenderProxySliver {
  _RenderSliverReveal(this._extent, {required this.onExtent});

  double _extent;
  set extent(double value) {
    if (value == _extent) return;
    _extent = value;
    markNeedsLayout();
  }

  ValueChanged<double> onExtent;
  bool _cut = false;
  final _clip = LayerHandle<ClipRectLayer>();

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(constraints, parentUsesSize: true);
    final whole = child.geometry!;
    if (whole.scrollOffsetCorrection != null) {
      geometry = whole;
      return;
    }
    onExtent(whole.scrollExtent);
    final end = _extent;
    if (!end.isFinite ||
        whole.scrollExtent <= end ||
        constraints.axisDirection != AxisDirection.down) {
      _cut = false;
      geometry = whole;
      return;
    }
    _cut = true;
    final paint = calculatePaintOffset(constraints, from: 0, to: end);
    final cache = calculateCacheOffset(constraints, from: 0, to: end);
    geometry = SliverGeometry(
      scrollExtent: end,
      paintExtent: paint,
      layoutExtent: paint,
      maxPaintExtent: end,
      cacheExtent: cache,
      hitTestExtent: paint,
      hasVisualOverflow: true,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || !child.geometry!.visible) {
      _clip.layer = null;
      return;
    }
    if (!_cut) {
      _clip.layer = null;
      context.paintChild(child, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTWH(0, 0, constraints.crossAxisExtent, geometry!.paintExtent),
      (context, offset) => context.paintChild(child, offset),
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    if (_cut && mainAxisPosition > geometry!.paintExtent) return false;
    return super.hitTestChildren(
      result,
      mainAxisPosition: mainAxisPosition,
      crossAxisPosition: crossAxisPosition,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}
