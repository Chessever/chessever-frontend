import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart'
    show EventViewSearch;
import 'package:chessever2/screens/for_you/for_you_screen.dart'
    show ForYouPageTabs;
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/page_spring.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Collections as a root: the dock's Collections tab.
///
/// It wears the bar every root wears ([HomeTopBarFrame]), composed as Home's
/// is: its pages are the bar, as text tabs in the root title voice
/// ([ForYouPageTabs]: About | Collections | Authors), with no way back. The
/// pages start where every root's page starts
/// ([HomeTopBarMetrics.headerExtent]), and swipe under the bar.
///
/// The bar folds away with the home shell's own scroll chrome (the
/// [ScrollChromeScope] the shell holds over every section), so reading a
/// catalog down sends the dock away exactly as on Home, and heading back up
/// brings both back. Tapping the dock's Collections slot again takes the
/// open page back to its top.
///
/// The catalog's search ([search]) floats over the tabs it searches, a
/// [SearchInkFab] riding the dock as Home's buttons do, and opens in the
/// bar's place (the app's one search mode, [SearchModeHost]), the field on
/// the bar's centre line, with the catalog's Filters beside it. Applied
/// filters are counted on the button's shoulder while the search is
/// closed. Leaving the section closes the search, so a search left open
/// out of sight never answers a back meant for another section.
class CollectionsRoot extends ConsumerStatefulWidget {
  const CollectionsRoot({
    super.key,
    required this.tabs,
    required this.pageBuilder,
    required this.search,
    this.initialTab = 0,
    this.onTabChanged,
    this.onHoldTab,
    this.holdHint,
  });

  /// The pages' names, as the bar's tabs.
  final List<String> tabs;

  /// Page `index`, ending [bottomPadding] further down than a pushed page
  /// would: the dock it runs under, and the search button where it floats.
  final Widget Function(BuildContext context, int index, double bottomPadding)
  pageBuilder;

  /// The catalog's search; its [EventViewSearch.controller] is required.
  final EventViewSearch search;

  final int initialTab;

  /// The page the root moved to (a tap or a swipe), to remember it.
  final ValueChanged<int>? onTabChanged;

  /// A held tab title.
  final ValueChanged<int>? onHoldTab;

  /// What assistive technology announces for holding tab `index`.
  final String Function(int index)? holdHint;

  @override
  ConsumerState<CollectionsRoot> createState() => _CollectionsRootState();
}

class _CollectionsRootState extends ConsumerState<CollectionsRoot>
    with TickerProviderStateMixin {
  late final PageController _pages = PageController(
    initialPage: widget.initialTab,
  );
  late int _selected = widget.initialTab;
  final Map<int, ScrollController> _scrolls = {};

  /// The bars' chrome when no shell holds one over the root (a test pumping
  /// it alone): the root then folds its own bar.
  ScrollChromeController? _ownChrome;

  SearchModeController get _search => widget.search.controller!;
  SearchModeController? _boundSearch;

  bool _searchesTab(int index) => widget.search.tabs?.contains(index) ?? true;

  @override
  void initState() {
    super.initState();
    _bindSearch();
  }

  @override
  void didUpdateWidget(CollectionsRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindSearch();
  }

  void _bindSearch() {
    final next = _search;
    if (identical(next, _boundSearch)) return;
    _boundSearch?.removeListener(_onSearchToggled);
    next.addListener(_onSearchToggled);
    _boundSearch = next;
  }

  /// The search opened or closed: the pages lock to (or free from) the tab
  /// it belongs to.
  void _onSearchToggled() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _boundSearch?.removeListener(_onSearchToggled);
    _pages.dispose();
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    _ownChrome?.dispose();
    super.dispose();
  }

  ScrollChromeController _chrome(BuildContext context) =>
      ScrollChromeScope.maybeOf(context) ??
      (_ownChrome ??= ScrollChromeController(vsync: this));

  /// Takes the open page back to its top on the tabs' spring; the bars come
  /// back with it.
  void _scrollToTop() {
    final scroll = _scrolls[_selected];
    if (scroll == null || !scroll.hasClients) return;
    unawaited(scroll.springToOffset(0, context: context));
  }

  /// A tab tapped on the bar. The one already open goes back to its top, as
  /// a reselected tab does across the app.
  void _tapTab(int index) {
    if (index == _selected) {
      _scrollToTop();
      return;
    }
    _select(index);
  }

  void _select(int index) {
    if (index < 0 || index >= widget.tabs.length) return;
    FocusScope.of(context).unfocus();
    if (index != _selected) {
      widget.onTabChanged?.call(index);
      // Another page opens with its bars in view.
      _chrome(context).show();
    }
    setState(() => _selected = index);
    if (!_pages.hasClients) return;
    // On a real spring: a tab tapped while the pages still move turns them
    // toward it, carrying their speed.
    unawaited(_pages.springTo(index, context: context));
  }

  /// How much further down than a pushed page's a page ends: the dock's
  /// share of the bottom inset (the shell hands its slot to the page as
  /// padding beyond the home indicator's), and the search button where it
  /// floats over the page.
  double _endPadding(BuildContext context, int index) {
    final barShare = math.max(
      0.0,
      MediaQuery.paddingOf(context).bottom -
          MediaQuery.viewPaddingOf(context).bottom,
    );
    return barShare + (_searchesTab(index) ? InkFabStack.extent() : 0);
  }

  /// The search's header in the bar's place: the field on the bar's centre
  /// line, the whole of it as tall as the bar's band, so neither the field
  /// nor the page under it moves as the two trade places.
  Widget _searchHeader(BuildContext context) {
    final search = widget.search;
    final onFilters = search.onFilters;
    final row = SearchHeaderMetrics.rowHeight;
    final top = math.max(
      0.0,
      HomeTopBarMetrics.topGap +
          (HomeTopBarMetrics.rowExtent(context) - row) / 2,
    );
    final bottom = math.max(
      0.0,
      HomeTopBarMetrics.bandExtent(context) -
          top -
          row -
          SearchHeaderMetrics.bottomGap,
    );
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: SearchModeHeader(
        hintText: search.hintText,
        rotatingHints: search.rotatingHints,
        textFieldKey: search.textFieldKey,
        closeKey: const ValueKey('collections_root_search_close'),
        trailing: [
          if (onFilters != null)
            SearchModeFilterButton(
              key: search.filterKey,
              count: search.badgeCount,
              onTap: onFilters,
            ),
        ],
      ),
    );
  }

  /// The search button over the tabs it searches, applied filters counted
  /// on its shoulder. It stays while the search is open: the search mode
  /// hides it, its glass having become the field, and flies the glass back
  /// into it as the search closes.
  Widget _searchFab() {
    if (!_searchesTab(_selected)) return const SizedBox.shrink();
    final search = widget.search;
    return InkFabStack(
      children: [
        SearchInkFab(
          key: const ValueKey('event_view_search_fab'),
          label: search.label,
          badgeCount: search.badgeCount,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final chrome = _chrome(context);
    final ownsChrome = identical(chrome, _ownChrome);
    final search = widget.search;

    // Leaving the section closes the search: kept out of sight, an open
    // search would hold the back that belongs to the section in view.
    ref.listen<BottomNavBarItem>(selectedBottomNavBarItemProvider, (_, next) {
      if (next != BottomNavBarItem.collections && _search.isSearching) {
        _search.close();
      }
    });
    // The dock's Collections slot tapped again: the open page goes back to
    // its top, on the tabs' spring, with its bars.
    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item != BottomNavBarItem.collections) return;
      if (previous != null && previous.sequence == next.sequence) return;
      chrome.show();
      _scrollToTop();
    });

    // The bar every root wears, with the pages as its row. The status
    // bar's strip stays outside the part that folds (below), so the band
    // folds up to the status bar, never into it.
    final band = MediaQuery.removeViewPadding(
      context: context,
      removeTop: true,
      child: HomeTopBarFrame(
        child: ForYouPageTabs(
          pageController: _pages,
          selectedIndex: _selected,
          labels: widget.tabs,
          onSelected: _tapTab,
          onHold: widget.onHoldTab ?? (_) {},
          holdHint: widget.holdHint,
        ),
      ),
    );

    Widget pages = PageView.builder(
      controller: _pages,
      // Searching holds the tab: the search belongs to it.
      physics: _search.pagePhysics(),
      itemCount: widget.tabs.length,
      onPageChanged: (index) {
        if (index == _selected) return;
        FocusScope.of(context).unfocus();
        widget.onTabChanged?.call(index);
        chrome.show();
        setState(() => _selected = index);
      },
      itemBuilder: (context, index) => PrimaryScrollController(
        controller: _scrolls.putIfAbsent(index, ScrollController.new),
        child: Builder(
          builder: (context) =>
              widget.pageBuilder(context, index, _endPadding(context, index)),
        ),
      ),
    );
    if (ownsChrome) {
      pages = ScrollChromeRegion(controller: chrome, child: pages);
    }

    final column = Column(
      children: [
        SizedBox(height: MediaQuery.viewPaddingOf(context).top),
        CollapsingChrome(
          controller: chrome,
          child: SizedBox(
            width: double.infinity,
            // The bar and the search trade places on the search mode's one
            // timeline: the bar stays mounted, exactly as it was left.
            child: SearchModeHeaderSlot(
              header: band,
              search: _searchHeader(context),
            ),
          ),
        ),
        Expanded(child: pages),
      ],
    );

    // This page's own Scaffold sits in the shell's body, which hands it the
    // dock's slot as bottom padding beyond the home indicator's: lifted by
    // that share, the button stands exactly where Home's do over the dock
    // (and where a pushed page's does with no dock).
    final dockShare = math.max(
      0.0,
      MediaQuery.paddingOf(context).bottom -
          MediaQuery.viewPaddingOf(context).bottom,
    );
    final scaffold = Scaffold(
      key: e2eKey(E2eIds.collectionsRoot),
      backgroundColor: colors.background,
      // The button leaves with the dock and comes back with it, as Home's
      // do (slide + glass fade, same spring), from the corner Home's stand
      // in.
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: dockShare),
        child: SlidingFabs(controller: chrome, child: _searchFab()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: column,
        ),
      ),
    );

    // The search mode owns the rest: the morph both ways, system back
    // (closing the search first), focus and keyboard, holding the bars
    // while typing, and the query.
    return SearchModeHost(
      controller: _search,
      chrome: chrome,
      debounce: search.debounce,
      onChanged: search.onChanged,
      onQuery: search.onQuery,
      onOpen: search.onOpen,
      onClose: search.onClose,
      child: scaffold,
    );
  }
}
